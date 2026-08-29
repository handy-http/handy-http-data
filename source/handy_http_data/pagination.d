module handy_http_data.pagination;

import handy_http_primitives;
import std.conv;

enum SortDir : string {
    ASC = "ASC",
    DESC = "DESC"
}

struct Sort {
    immutable string attribute;
    immutable SortDir dir;

    static Optional!Sort parse(string expr) {
        import std.string;
        string[] parts = expr.split(",");
        if (parts.length == 1) return Optional!Sort.of(Sort(parts[0], SortDir.ASC));
        if (parts.length != 2) return Optional!Sort.empty;
        string attr = parts[0];
        string dirExpr = parts[1];
        SortDir d;
        if (dirExpr == SortDir.ASC) {
            d = SortDir.ASC;
        } else if (dirExpr == SortDir.DESC) {
            d = SortDir.DESC;
        } else {
            return Optional!Sort.empty;
        }
        return Optional!Sort.of(Sort(attr, d));
    }
}

/**
 * Represents a request for a page of items from a paginated data source.
 */
struct PageRequest {
    /**
     * The requested page number, starting from 1 for the first page, or zero
     * for an unpaged request.
     */
    uint page;

    /**
     * The maximum number of items to include in each page of results.
     */
    ushort size;

    /**
     * A list of sorts to apply.
     */
    Sort[] sorts;

    /**
     * Tells if this page request is unpaged. By convention, if the requested
     * page is zero, then the request is for all data, unpaged.
     * Returns: True if this is an unpaged request (requested page is zero).
     */
    bool isUnpaged() const {
        return page < 1;
    }

    /**
     * Convenience function to get an unpaged request.
     * Returns: A new unpaged request.
     */
    static PageRequest unpaged() {
        return PageRequest(0, 0, []);
    }

    /**
     * Parses a page request from an HTTP request, using standard query
     * parameter names.
     * Params:
     *   request = The request to parse from.
     *   defaults = Defaults to use if the HTTP request doesn't specify certain
     *              parts of the the page request.
     * Returns: The parsed page request.
     */
    static PageRequest parse(in ServerHttpRequest request, in PageRequest defaults) {
        import std.algorithm;
        import std.array;
        uint pg = request.getParamAs!uint("page", defaults.page);
        ushort sz = request.getParamAs!ushort("size", defaults.size);
        Sort[] s = request.queryParams
            .filter!(p => p.key == "sort" && p.values.length > 0)
            .map!(p => Sort.parse(p.values[0]))
            .filter!(o => !o.isNull)
            .map!(o => o.value)
            .array;
        if (s.length == 0 && defaults.sorts.length > 0) {
            s = defaults.sorts.dup;
        }
        return PageRequest(pg, sz, s.dup);
    }

    /**
     * Converts this page request to an SQL expression of the form
     * "ORDER BY a ASC, b DESC LIMIT N OFFSET M".
     * Returns: The SQL expression.
     */
    string toSql() const {
        import std.array;
        auto app = appender!string;
        app ~= this.toOrderClause();
        if (!isUnpaged()) {
            app ~= "LIMIT ";
            app ~= size.to!string;
            app ~= " OFFSET ";
            app ~= ((page - 1) * size).to!string;
        }
        return app[];
    }

    /**
     * Converts the list of sort parameters in this page request to an SQL
     * "ORDER BY" expression.
     * Returns: The SQL expression.
     */
    string toOrderClause() const {
        import std.array;
        auto app = appender!string;
        if (sorts.length > 0) {
            app ~= "ORDER BY ";
            for (size_t i = 0; i < sorts.length; i++) {
                app ~= sorts[i].attribute;
                app ~= " ";
                app ~= cast(string) sorts[i].dir;
                if (i + 1 < sorts.length) app ~= ",";
            }
            app ~= " ";
        }
        return app[];
    }

    /**
     * Gets a request for the next page.
     * Returns: A request for the next page.
     */
    PageRequest next() const {
        if (isUnpaged) return PageRequest(page, size, sorts.dup);
        return PageRequest(page + 1, size, sorts.dup);
    }

    /**
     * Gets a request for the previous page, if there is one. If we're already
     * at page 1, this returns a copy of this request.
     * Returns: A request for the previous page.
     */
    PageRequest prev() const {
        if (isUnpaged || page == 1) return PageRequest(page, size, sorts.dup);
        return PageRequest(page - 1, size, sorts.dup);
    }
}

/**
 * Container for a paginated response, which contains the actual page of items,
 * as well as some metadata to assist any API client in navigating to other
 * pages.
 */
struct Page(T) {
    /// The list of items in this page.
    T[] items;
    /// The page request that produced this page.
    PageRequest pageRequest;
    /// The total number of elements that were found.
    ulong totalElements;
    /// The total number of pages needed to show all elements.
    ulong totalPages;
    /// Whether this page is the first page.
    bool isFirst;
    /// Whether this page is the last page.
    bool isLast;

    /**
     * Maps the items of this page to another type using the given mapping
     * function `fn`.
     * Params:
     *   fn = A mapping function that converts page items to another type.
     * Returns: A page of converted items.
     */
    Page!U mapTo(U)(U delegate(T) fn) {
        import std.algorithm : map;
        import std.array : array;
        return Page!(U)(items.map!(fn).array, pageRequest, totalElements, totalPages, isFirst, isLast);
    } 

    /**
     * Constructs a page of items.
     * Params:
     *   items = The list of items.
     *   pageRequest = The original page request.
     *   totalCount = The total number of results.
     * Returns: The page.
     */
    static Page of(T[] items, in PageRequest pageRequest, ulong totalCount) {
        ulong pageCount = getTotalPageCount(totalCount, pageRequest.size);
        return Page(
            items,
            PageRequest(pageRequest.page, pageRequest.size, pageRequest.sorts.dup),
            totalCount,
            pageCount,
            pageRequest.page == 1,
            pageRequest.page == pageCount || totalCount == 0
        );
    }
}

private ulong getTotalPageCount(ulong totalElements, ulong pageSize) {
    if (pageSize == 0) return totalElements > 0 ? 1 : 0;
    return totalElements / pageSize + (totalElements % pageSize > 0 ? 1 : 0);
}

unittest {
    assert(getTotalPageCount(5, 1) == 5);
    assert(getTotalPageCount(5, 2) == 3);
    assert(getTotalPageCount(5, 3) == 2);
    assert(getTotalPageCount(5, 4) == 2);
    assert(getTotalPageCount(5, 5) == 1);
    assert(getTotalPageCount(5, 6) == 1);
    assert(getTotalPageCount(5, 123) == 1);
    assert(getTotalPageCount(250, 100) == 3);
    assert(getTotalPageCount(25, 0) == 1);
    assert(getTotalPageCount(0, 0) == 0);
}
