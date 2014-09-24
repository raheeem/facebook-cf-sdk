/**
* FacebookRequest - Models a request to the Facebook APIs
*/
component name="FacebookRequest" accessors="false" {

    // ---- constants ----

    /**
	* SDK Version
	*/
	variables.VERSION = "4.0.0alpha1";
    /**
	* Graph API version
	*/
	variables.GRAPH_API_VERSION = "v2.0";
    /**
	* Graph API entry point URL
	*/
	variables.BASE_GRAPH_URL = "https://graph.facebook.com";

    // ---- properties ----

    /**
	* The session used for this request
	*/
    variables.fbsession = "";
    /**
	* The HTTP method for the request
	*/
    variables.method = "";
    /**
	* The path for the request
	*/
    variables.path = "";
    /**
	* The parameters for the request
	*/
    variables.params = "";
    /**
	* The session used for this request
	*/
    variables.version = "";
    /**
	* The session used for this request
	*/
    variables.etag = "";


    /**
	* Returns the FacebookSession object
	*
	* @return FacebookSession object
	*/
    public FacebookSession function getFBSession() {
        return variables.fbsession;
    }

    /**
	* Returns the path
	*
	* @return Path
	*/
    public string function getPath() {
        return variables.path;
    }

    /**
	* Returns the params struct
	*
	* @return Parameters struct
	*/
    public struct function getParameters() {
        return variables.params;
    }

    /**
	* Returns the associated method
	*
	* @return HTTP method
	*/
    public string function getMethod() {
        return variables.method;
    }

    /**
	* Returns the ETag sent with the request
	*
	* @return eTag
	*/
    public string function getETag() {
        return variables.etag;
    }

    /**
    * FacebookRequest - Returns a new request using the given session. Optional parameters hash will be sent with the request. This object is immutable.
    *
    * @session.hint FacebookSession object
    * @method.hint HTTP method
    * @path.hint ?
    * @parameters.hint Struct with request parameters
    * @version.hint API version
    * @etag.hint eTag
    */
    public void function init(required FacebookSession session, required string method, required string path, struct parameters = {}, string version = "", string etag = "") {
        // CFC Metadata
        var metadata = getComponentMetadata("FacebookRequest");
        if (!StructKeyExists(metadata,"requestCount")) {
            lock name="FacebookRequest.metadata.requestCount" timeout="10" {
                metadata["requestCount"] = 0;
            }
        }

        var params = arguments.parameters;

        variables.fbsession = arguments.session;
        variables.method = arguments.method;
        variables.path = arguments.path;

        if (Len(arguments.version)) {
            variables.version = arguments.version;
        } else {
            variables.version = variables.GRAPH_API_VERSION;
        }

        variables.etag = arguments.etag;

        // TODO: Implement getToken
        if (!StructKeyExists(params,"access_token")) {
            params["access_token"] = variables.fbsession.getToken();
        }

        // TODO: Implement getUseAppSecretProof() --- is a static property in FacebookRequest
        if (variables.session.getUseAppSecretProof() && !StructKeyExists(params,"appsecret_proof")) {
            params["appsecret_proof"] = getAppSecretProof(params["access_token"]);
        }

        variables.params = params;
    }

    /**
    * Returns the base Graph URL.
    *
    * @return Base Graph URL.
    */
    package string function getRequestURL() {
        return variables.BASE_GRAPH_URL & "/" & variables.version & variables.path;
    }


    /**
    * Makes the request to Facebook and returns the result.
    *
    * @return FacebookResponse object
    */
    public FacebookResponse function execute() {
        var url = getRequestURL();
        var params = getParameters();
        var httpService = "";
        var response = "";
        var eTagHit = false;
        var headers = {};
        var eTagReceived = "";
        var decodedResult = "";
        var out = {};

        if (variables.method == "GET") {
            url = appendParamsToURL(url,params);
            params = {};
        }

        // TODO: make timeout configurable, also look into refactoring this into a http class analogues to PHP. Not sure if that's needed for CFML though.
        httpService = newHttp(url=url,method=variables.method,timeout=60)
        httpService.addParams(type="header",name="User-Agent",value="fb-cfml-#variables.version#");
        httpService.addParams(type="header",name="Accept-Encoding",value="*"); // let's support all available encodings

        // ETag
        if (Len(variables.etag)) {
            httpService.addParams(type="header",name="If-None-Match",value=variables.etag);
        }

        // The actual params struct needs to potentiall be passed in here?
        response = httpService.send().getPrefix();

        lock name="FacebookRequest.metadata.requestCount" timeout="10" {
            metadata["requestCount"]++;
        }

        // TODO: see top - maybe app scoped variable?
        variables.requestCount++;

        eTagHit = iif(response.statusCode == 304,true,false)

        headers = response.responseHeader;

        if (StructKeyExists(headers,"ETag")) {
            eTagReceived = headers["ETag"];
        }

        decodedResult = deserializeJSON(response.fileContent);

        if (!isArray(decodedResult) && !isStruct(decodedResult)) {
            out = CreateObject("component","FacebookHelper").parseString(result.fileContent)

            return new FacebookResponse(this,out,response.fileContent,eTagHit,eTagReceived);
        }

        if (StructKeyExists(decodedResult,"error")) {
            throw(type="FacebookRequestException",message="Something went wrong in the request execution");
        /*
        if (isset($decodedResult->error)) {
            throw FacebookRequestException::create(
            $result,
            $decodedResult->error,
            $connection->getResponseHttpStatusCode()
            );
        }
        */
        }

        return new FacebookResponse(this,decodedResult,response.fileContent,eTagHit,eTagReceived);
    }

    /**
    * Generate and return the appsecret_proof value for an access_token
    *
    * @token.hint access_token to be used
    *
    * @return appsecret_proof
    */
    public string function getAppSecretProof(required string token) {
        var facebookSession = new FacebookSession();

        return new FacebookHelper.hashHmacSHA256(token, facebookSession.getTargetAppSecret());
    }

    /**
    * Gracefully appends params to the URL.
    *
    * @url.hint URL
    * @params.hint Struct with additional parameters
    *
    * @return Modified URL
    */
    public string function appendParamsToUrl(required string url, struct parameters = {}) {
        var facebookHelper = CreateObject("component","FacebookHelper");
        var params = arguments.parameters;
        var path = "";
        var queryString = "";
        var queryStruct = {};

        if (structIsEmpty(arguments.parameters)) {
            return arguments.url;
        }

        if (!findNoCase("?",arguments.url)) {
            return arguments.url & "?" &  facebookHelper.structToQueryString(arguments.parameters);
        }

        path = ListGetAt(arguments.url,1,"?");
        queryString = ListGetAt(arguments.url,2,"?");

        queryStruct = facebookHelper.parseString(queryString)

        // Favour params from the original URL over params
        StructAppend(params,queryStruct);

        return path & "?" &  facebookHelper.structToQueryString(params);
    }
}
