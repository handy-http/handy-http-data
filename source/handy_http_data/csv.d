module handy_http_data.csv;

import streams;
import handy_http_primitives : Optional;
import std.conv : to;

/**
 * A utility that allows for convenient writing of data to an output
 * stream in CSV format.
 */
struct CsvStreamWriter(S) if (isByteOutputStream!S) {
    S stream;
    private bool atStartOfRow = true;
    private StreamResult result;

    this(S outputStream) {
        this.stream = outputStream;
    }

    /**
     * Appends a value to the current row.
     * Params:
     *   value = The value to append.
     */
    ref append(T)(T value) {
        if (!atStartOfRow) {
            result = stream.writeToStream([',']);
            throwIfError(result);
        }
        import std.regex : replaceAll, regex;
        import std.string : indexOf;
        string s = value.to!string();
        bool shouldValueBeQuoted = indexOf(s, '"') != -1 ||
            indexOf(s, ',') != -1 ||
            indexOf(s, '\n') != -1;
        s = replaceAll(value.to!string(), regex("\""), "\"\"");
        if (shouldValueBeQuoted) {
            s = "\"" ~ s ~ "\"";
        }
        result = stream.writeToStream(cast(ubyte[]) s);
        throwIfError(result);
        atStartOfRow = false;
        return this;
    }

    /**
     * Appends a new line, moving to the next row.
     */
    ref newLine() {
        result = stream.writeToStream(['\n']);
        throwIfError(result);
        static if (isFlushableStream!S) {
            auto optionalError = stream.flushStream();
            throwIfError(optionalError);
        }
        atStartOfRow = true;
        return this;
    }

    private void throwIfError(StreamResult result) {
        if (result.hasError) {
            throw new Exception("Stream error: " ~ result.error.message.to!string);
        }
    }

    private void throwIfError(Optional!StreamError result) {
        if (!result.isNull) {
            throw new Exception("Stream error: " ~ result.value.message.to!string);
        }
    }
}
