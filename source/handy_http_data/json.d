/**
 * Defines functions to read and write JSON values when handling HTTP requests.
 */
module handy_http_data.json;

import streams;
import handy_http_primitives.request;
import handy_http_primitives.response;
import asdf;

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
    try {
        string requestBody = request.readBodyAsString(false);
        return deserialize!T(requestBody);
    } catch (SerdeException e) {
        throw new HttpStatusException(HttpStatus.BAD_REQUEST, e.msg, e);
    }
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
    try {
        string responseBody = serializeToJson(bodyContent);
        response.headers.remove("Content-Type");
        response.headers.remove("Content-Length");
        response.headers.add("Content-Type", "application/json");
        response.headers.add("Content-Length", to!string(responseBody.length));
        StreamResult result = response.outputStream.writeToStream(cast(ubyte[]) responseBody);
        if (result.hasError) {
            StreamError err = result.error;
            throw new HttpStatusException(HttpStatus.INTERNAL_SERVER_ERROR, err.message);
        }
    } catch (SerdeException e) {
        throw new HttpStatusException(HttpStatus.INTERNAL_SERVER_ERROR, e.msg, e);
    }
}
