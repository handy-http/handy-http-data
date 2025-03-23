/**
 * Defines functions for reading and writing XML content while handling HTTP
 * requests, using the dxml library: https://code.dlang.org/packages/dxml
 */
module handy_http_data.xml;

import handy_http_primitives.request;
import handy_http_primitives.response;
import dxml.dom;
import dxml.writer;
import std.array : appender, Appender;
import streams;

/**
 * Reads an XML request body.
 * Params:
 *   request = The request to read from.
 * Returns: The DOMEntity representing the XML payload.
 */
DOMEntity!string readXMLBody(ref ServerHttpRequest request) {
    string contentType = request.getHeaderAs!string("Content-Type");
    if (!(contentType == "application/xml" || contentType == "text/xml")) {
        throw new HttpStatusException(HttpStatus.UNSUPPORTED_MEDIA_TYPE, "Non-XML Content-Type header.");
    }
    string bodyContent = request.readBodyAsString(false);
    return parseDOM(bodyContent);
}

/**
 * Writes an XML response body, by using the provided delegate function to
 * compose the XML tag tree using a provided XMLWriter.
 *
 * See https://jmdavisprog.com/docs/dxml/0.4.4/dxml_writer.html#.xmlWriter
 * Params:
 *   response = The HTTP response to write to.
 *   dg = The delegate function that will be called to generate the XML.
 */
void writeXMLBody(ref ServerHttpResponse response, void delegate(ref XMLWriter!(Appender!string)) dg) {
    import std.conv : to;
    auto writer = xmlWriter(appender!string());
    dg(writer);
    string xmlContent = writer.output[];
    response.headers.remove("Content-Type");
    response.headers.add("Content-Type", "application/xml");
    response.headers.add("Content-Length", to!string(xmlContent.length));
    StreamResult result = response.outputStream.writeToStream(cast(ubyte[]) xmlContent);
    if (result.hasError) {
        StreamError err = result.error;
        throw new HttpStatusException(HttpStatus.INTERNAL_SERVER_ERROR, cast(string) err.message);
    }
}
