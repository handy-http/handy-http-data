/**
 * Defines functions to read and write JSON values when handling HTTP requests.
 */
module handy_http_data.json;

import streams;
import handy_http_primitives.request;
import handy_http_primitives.response;

/**
 * Reads a JSON value from the body of the given HTTP request, parsing it using
 * the ASDF library according to the template type T.
 *
 * Throws a BAD_REQUEST HttpStatusException if deserialization fails.
 * Params:
 *   request = The request to read the JSON from.
 * Returns: The value that was read.
 */
T readJsonBodyAs(T)(ref ServerHttpRequest request) {
    import asdf : deserialize, SerdeException;
    try {
        string requestBody = request.readBodyAsString(false);
        return deserialize!T(requestBody);
    } catch (SerdeException e) {
        throw new HttpStatusException(HttpStatus.BAD_REQUEST, e.msg, e);
    }
}

unittest {
    import handy_http_primitives.builder;
    ServerHttpRequest request = ServerHttpRequestBuilder()
        .withBody("{\"key\": \"value\"}")
        .withHeader("Content-Length", "16")
        .build();
    struct TestStruct {
        string key;
    }
    TestStruct testStruct = readJsonBodyAs!TestStruct(request);
    assert(testStruct.key == "value");
}

/** 
 * Writes a JSON value to the body of the given HTTP response, serializing it
 * using the ASDF library. Will also set Content-Type and Content-Length
 * headers before writing.
 *
 * Throws an INTERNAL_SERVER_ERROR HttpStatusException if serialization or
 * writing fails.
 * Params:
 *   response = The response to write to.
 *   bodyContent = The content to write.
 */
void writeJsonBody(T)(ref ServerHttpResponse response, in T bodyContent) {
    import std.conv : to;
    import std.traits : isArray;
    import std.json;
    import asdf : serializeToJson, SerdeException;
    try {
        static if (isArray!T && bodyContent.length == 0) {
            string responseBody = "[]";
        } else static if (is(T == JSONValue)) {
            string responseBody = bodyContent.toString();
        } else {
            string responseBody = serializeToJson(bodyContent);
        }
        response.headers.remove("Content-Type");
        response.headers.remove("Content-Length");
        response.headers.add("Content-Type", "application/json");
        response.headers.add("Content-Length", to!string(responseBody.length));
        StreamResult result = response.outputStream.writeToStream(cast(ubyte[]) responseBody);
        if (result.hasError) {
            StreamError err = result.error;
            throw new HttpStatusException(HttpStatus.INTERNAL_SERVER_ERROR, cast(string) err.message);
        }
    } catch (SerdeException e) {
        throw new HttpStatusException(HttpStatus.INTERNAL_SERVER_ERROR, e.msg, e);
    }
}

unittest {
    import handy_http_primitives.builder;
    ArrayOutputStream!ubyte outputStream = byteArrayOutputStream();
    ServerHttpResponse response = ServerHttpResponseBuilder()
        .withOutputStream(&outputStream)
        .build();
    struct TestStruct {
        string key;
    }
    TestStruct testStruct = TestStruct("value");
    writeJsonBody(response, testStruct);
    assert(response.headers["Content-Type"] == "application/json");
    const writtenBody = cast(string) outputStream.toArrayRaw();
    assert(writtenBody == "{\"key\":\"value\"}");
}
