section ManageEngineConnector;

// See the Manage Engine API documentation here:
// https://www.manageengine.com/products/service-desk/sdpod-v3-api/SDPOD-V3-API.html#register-your-application

// And the documentation for creating a OAUTH Power BI data connector here:
// https://docs.microsoft.com/en-us/power-query/samples/github/readme

// This is effectively the Github sample (which uses OAUTH) tweeked to work with Manage Engine.

// To write diagnostic tracing:
// dt = Diagnostics.Trace(TraceLevel.Information, "SeriesReport Error", () => "test3", true),

//
// OAuth configuration settings
//
// The client ID and secret were generated here 'https://accounts.zoho.com/developerconsole'.
// The client type is 'web server' where you specify a client name and redirect URI.
// The redirect URI there must correspond to the one below, and comes from the Power BI documentation.
// https://www.manageengine.com/products/service-desk/sdpod-v3-api/SDPOD-V3-API.html#register-your-application

client_id = Text.FromBinary(Extension.Contents("client_id"));
client_secret = Text.FromBinary(Extension.Contents("client_secret"));
redirect_uri = "https://oauth.powerbi.com/views/oauthredirect.html";
windowWidth = 1200;
windowHeight = 1000;

//
// Exported functions
//
// These functions are exported to the M Engine (making them visible to end users), and associates 
// them with the specified Data Source Kind. The Data Source Kind is used when determining which 
// credentials to use during evaluation. Credential matching is done based on the function's parameters. 
// All data source functions associated to the same Data Source Kind must have a matching set of required 
// function parameters, including type, name, and the order in which they appear.

[DataSource.Kind="ManageEngineConnector"]
shared ManageEngineConnector.GetMultiple = Value.ReplaceType(ManageEngine.GetMultiple,
    type function (
        url as Uri.Type,
        optional fieldsRequired as list,
        optional searchCriteria as nullable text,
        optional sortField as nullable text,
        optional sortOrder as nullable text,
        optional count as nullable number,
        optional startIndex as nullable number
    ) as nullable table
);

[DataSource.Kind="ManageEngineConnector"]
shared ManageEngineConnector.GetSingle = Value.ReplaceType(ManageEngine.GetSingle, type function (url as Uri.Type, optional fieldsRequired as list) as nullable table);

//
// Data Source definition
//
ManageEngineConnector = [
    TestConnection = (dataSourcePath) => {"ManageEngineConnector.GetMultiple", dataSourcePath},
    Authentication = [
        OAuth = [
            StartLogin = StartLogin,
            FinishLogin = FinishLogin,
            Label = Extension.LoadString("AuthenticationLabel")
        ]
    ]
];

//
// UI Export definition
//
ManageEngineConnector.UI = [
    Beta = true,
    ButtonText = { Extension.LoadString("FormulaTitle"), Extension.LoadString("FormulaHelp") },
    SourceImage = ManageEngineConnector.Icons,
    SourceTypeImage = ManageEngineConnector.Icons
];

ManageEngineConnector.Icons = [
    Icon16 = { Extension.Contents("PowerBIManageEngineExtension16.png"), Extension.Contents("PowerBIManageEngineExtension20.png"), Extension.Contents("PowerBIManageEngineExtension24.png"), Extension.Contents("PowerBIManageEngineExtension32.png") },
    Icon32 = { Extension.Contents("PowerBIManageEngineExtension32.png"), Extension.Contents("PowerBIManageEngineExtension40.png"), Extension.Contents("PowerBIManageEngineExtension48.png"), Extension.Contents("PowerBIManageEngineExtension64.png") }
];

MAX_ROWS=100;
MAX_ROWS_STR=Text.From(MAX_ROWS);

ManageEngine.GetSingle = (url as text,optional fieldsRequired as list) as nullable table =>
    ManageEngine.Get(url, fieldsRequired, false);

// Get data from a manage engine API URL: internal helper function
ManageEngine.Get = (
    url as text,
    fieldsRequired as list,
    optional multiple as nullable logical,
    optional searchCriteria as nullable text,
    optional sortField as nullable text,
    optional sortOrder as nullable text,
    optional startIndex as nullable number,
    optional count as nullable number) as nullable table =>
    let
        countToRequest=
            if(count=null)then
                MAX_ROWS
            else if(count>MAX_ROWS)then
                MAX_ROWS
            else
                count,
        fullUrl=BuildGetFullUrl(url, fieldsRequired, multiple, searchCriteria, sortField, sortOrder, startIndex, countToRequest),
        content = Web.Contents(fullUrl, [Headers=[Accept="application/v3+json"], ManualStatusHandling={400, 403, 404, 415, 500}]),
        json = Json.Document(content),
        jsonAsTable=Record.ToTable(json),
        errors=GetErrorMessages(jsonAsTable),
        success=if(errors=null)then true else false,
        successWithData=success and Table.RowCount(jsonAsTable)>0,
        // Get the record as a list
        outputAsRecord =
            if(success)then
                if(multiple)then
                    Table.ExpandListColumn(
                        Table.RemoveColumns(
                            Table.SelectRows(jsonAsTable,each [Name]<>"response_status" and [Name]<>"list_info"),
                            {"Name"}
                        ),
                        "Value"
                    )
                else
                    Table.RemoveColumns(
                        Table.SelectRows(jsonAsTable,each [Name]<>"response_status" and [Name]<>"list_info"),
                        {"Name"}
                    )
            else
                null,
        output=
            if(successWithData)then
                ExpandGetResults(outputAsRecord, fieldsRequired, 1)
            else if(success)then
                jsonAsTable
            else
                errors,
        nextStartIndex=if(success and multiple)then NextStartIndex(jsonAsTable) else null
    in
        output meta [nextStartIndex=nextStartIndex, success=success];

AddExpandedColumn = (theList as list,columnPrefix as nullable text, expanded as text) as list =>

    let
        existingListsForColumn=List.Select(theList,(iterList) => iterList{0} = columnPrefix),
        otherColumnLists=List.Select(theList,(iterList) => iterList{0} <> columnPrefix),
        updatedListForColumn=
            if(List.Count(existingListsForColumn)=1)then
                List.Combine({existingListsForColumn{0}, {expanded}})
            else
                {columnPrefix, expanded}

    in
        List.Combine({{updatedListForColumn}, otherColumnLists});
    
ConditionalAppend = (current as nullable text, seperator as text, new as text) => 
    if(current=null or current="")then
        new
    else
        current & seperator & new;

ExpandGetResultsAccumulate = (columnPrefix as nullable text, thisDepth as number, depthToDo as number, inProgress as list, item as any) as list =>

    let
        itemIsList=Type.Is(Value.Type(item),type list),
        rv=
            if(thisDepth = depthToDo)then
                if(itemIsList)then
                    AddExpandedColumn(inProgress,columnPrefix,item{0})
                else
                    AddExpandedColumn(inProgress,columnPrefix,item)
            else
                if(itemIsList)then
                    List.Accumulate(List.Range(item,1),inProgress,(innerInProgress,innerItem) => ExpandGetResultsAccumulate(
                        ConditionalAppend(columnPrefix,".",item{0}), thisDepth+1, depthToDo, innerInProgress,innerItem
                    ))
                else
                    inProgress
    in
        rv;

AppendColumnPrefix = (theList as list,columnPrefix as text) as list =>
    List.Transform(theList,each columnPrefix & "." & _);

ExpandGetResults = (results as table, fieldsRequired as list, nestLevel as number) as table =>
    let
        fieldsToExpand=
            List.Accumulate(fieldsRequired,{},(inProgress,item) => ExpandGetResultsAccumulate(null, 1, nestLevel, inProgress, item)),
        haveFieldsToExpand=List.Count(fieldsToExpand)>0,
        resultsExpanded=
            if(haveFieldsToExpand)then
                if(nestLevel=1)then
                    // There will only be one list at this level
                    Table.ExpandRecordColumn(results, "Value", List.Range(fieldsToExpand{0},1))
                else
                    List.Accumulate(fieldsToExpand,results,(inProgressResults,iterExpandFields) =>
                        Table.ExpandRecordColumn(inProgressResults, iterExpandFields{0}, List.Range(iterExpandFields,1), AppendColumnPrefix(
                            List.Range(iterExpandFields,1),
                            iterExpandFields{0}
                        )
                    ))
            else
                results,
        recursiveResultsExpanded=
            if(haveFieldsToExpand)then
                ExpandGetResults(resultsExpanded,fieldsRequired,nestLevel+1)
            else
                results
    in
        recursiveResultsExpanded;

BuildGetFullUrl = (
    url as text,
    fieldsRequired as list,
    multiple as logical,
    searchCriteria as nullable text,
    sortField as nullable text,
    sortOrder as nullable text,
    startIndex as nullable number,
    countToRequest as nullable number
) as text =>

    let
        searchJson=
            if(searchCriteria<>null)then
                ",""search_criteria"":" & searchCriteria
            else
                "",
        sortJson=
            if(sortField <> null and sortOrder<>null)then
                ",""sort_field"": """ & sortField & """, ""sort_order"": """ & sortOrder &""""
            else
                "",

        fieldsRequiredJson=
            ",""fields_required"":""[" & CreateFieldsRequiredCSV(fieldsRequired) & "]""",

        inputData=
            if(multiple)then
                "{""list_info"":{""start_index"":" & Text.From(startIndex) & ",""row_count"":" &
                    Text.From(countToRequest) & fieldsRequiredJson & searchJson & sortJson & "}}"
            else
                null,

        fullUrl =
            if(multiple)then
                Text.From(url & "?" & Uri.BuildQueryString([input_data = inputData]))
            else
                url
    in
        fullUrl;

CreateFieldsRequiredCSVAccFunction = (inProgress as text, item as any) as text =>

    let
        itemText=
            if(Type.Is(Value.Type(item), type list))then
                item{0}
            else
                item,
        rv=
            if(inProgress="")then
                itemText
            else
                inProgress & "," & itemText
    in
        rv;


CreateFieldsRequiredCSV = (fieldsRequired as list) as text =>

    let
        rv=List.Accumulate(fieldsRequired,"",CreateFieldsRequiredCSVAccFunction)
    in
        rv;

CreateCSVFromList = (theList as list) as text =>

    let
        rv=List.Accumulate(theList,"",
            (inProgress,item) => if(inProgress="")then Text.From(item) else inProgress & "," & Text.From(item)) as text
    in
        rv;

// Returns a table with a single column which is the returned info as a record. If there are error(s), these are
// returned instead.
ManageEngine.GetMultiple = (
    url as text,
    optional fieldsRequired as list,
    optional searchCriteria as nullable text,
    optional sortField as nullable text,
    optional sortOrder as nullable text,
    optional count as nullable number,
    optional initialStartIndex as nullable number
) as nullable table =>

    Table.GenerateByPageEx(count, (previous, numRemaining) =>
        let
            initialStartIndex=if(initialStartIndex=null) then 0 else initialStartIndex,
            // If we have a previous page, get its next start index from metadata on the page.
            currentStartIndex = if (previous <> null) then Value.Metadata(previous)[nextStartIndex] else initialStartIndex /* Get the first */,
            // If we have a previous page, but don't have a next link, then we're done paging.
            // Otherwise retrieve the next page.
            current = if (currentStartIndex<>null) then ManageEngine.Get(url, fieldsRequired, true, searchCriteria, sortField, sortOrder, currentStartIndex, numRemaining) else null,
            // If we got data back from the current page, get the link for the next page
            nextStartIndex = if (current <> null) then Value.Metadata(current)[nextStartIndex] else null,
            success=false
        in
            current meta [nextStartIndex=nextStartIndex]
    );

// For a given JSON document as a table, return the error messages as a table with 2 columns, or null if there are no
// errors
GetErrorMessages = (jsonAsTable as table) as nullable table =>
    let
        responseStatus=Table.FindText(jsonAsTable, "response_status"),
        hasResponseStatus=if(Table.RowCount(responseStatus)>0) then true else false,
        responsesAsList=
            if(hasResponseStatus)then
                if(Type.Is(Value.Type(responseStatus{0}[Value]), type record))then
                    // Turn the single response status response into a list
                    {responseStatus{0}[Value]}
                else
                    // The response_status node contains a list of records. The list may include a success item as well as
                    // error items
                    responseStatus{0}[Value]
            else
                null,
        unsuccessfulResponseStatusItems=
            if(hasResponseStatus)then
                List.Select(responsesAsList, IsNotSuccessResponseStatusItem)
            else
                null,
        hasErrors=
            if(unsuccessfulResponseStatusItems <> null and List.Count(unsuccessfulResponseStatusItems)>0)then
                true
            else
                false,
        errorMessagesAsList=
            if(hasErrors)then
                List.Transform(unsuccessfulResponseStatusItems, GetErrorsFromResponseStatusItem)
            else
                null,
        output=
            if(hasErrors)then
                Table.ExpandRecordColumn(
                    Table.ExpandListColumn(
                        Table.FromList(errorMessagesAsList,Splitter.SplitByNothing()),
                        "Column1"
                    ),
                    "Column1",
                    {"msg", "code"}
                )
            else if(hasResponseStatus)then
                null
            else
                #table({"msg", "code"},{{"No 'response_status' in returned JSON from API.",0}})
    in
        output;

// For a given response status item record, return the error information as a list of [msg,code] records
GetErrorsFromResponseStatusItem = (item as record) as list =>
    let
    in
        List.Transform(item[messages], GetErrorRecordFromMessage);

GetErrorRecordFromMessage = (msg as record) as record =>
    let
        msgText=msg[message],
        msgCode=msg[status_code]
        in
            [msg=msgText, code=msgCode];

// For a given response status item record, is this a success?
IsNotSuccessResponseStatusItem = (item as record) as logical =>
    let
        // The status code is not always returned - at least according to the error code examples...
        statusCodeOptional=Record.FieldOrDefault(item,"status_code",null),
        isNotSuccessItem=if(statusCodeOptional<>null and statusCodeOptional=2000)then false else true
    in
        isNotSuccessItem;

// This function returns the next start index or null, depending on the current start index and the downloaded JSON.
// If the current start index=1000 and the JSON document "has_more_rows" value is true, the next start index will be 1000 + MAX_ROWS
NextStartIndex = (jsonAsTable as table) as nullable number =>
    let
        listInfoRow=Table.FindText(jsonAsTable, "list_info"),
        expandedListInfo=
            if(listInfoRow <> null) then
                Table.ExpandRecordColumn(listInfoRow,"Value",{"has_more_rows","start_index","row_count"})
            else
                null,
        hasMoreRows=
            if(expandedListInfo <> null) then
                List.First(expandedListInfo[has_more_rows])
            else
                false,
        nextStartIndex=
            if(hasMoreRows)then
               List.First(expandedListInfo[start_index])+List.First(expandedListInfo[row_count]) 
            else
                null
    in
        nextStartIndex;

//
// OAuth2 flow definition
//

// scopes hard coded to request read access only. 
StartLogin = (resourceUrl, state, display) =>
    let
        AuthorizeUrl = "https://accounts.zoho.com/oauth/v2/auth?" & Uri.BuildQueryString([
			response_type = "code",
            client_id = client_id,
            scope = "SDPOnDemand.requests.READ,SDPOnDemand.changes.READ,SDPOnDemand.projects.READ,SDPOnDemand.assets.READ,SDPOnDemand.setup.READ,SDPOnDemand.general.READ",
            state = state,
            redirect_uri = redirect_uri,
			access_type = "offline"])
    in
        [
            LoginUri = AuthorizeUrl,
            CallbackUri = redirect_uri,
            WindowHeight = windowHeight,
            WindowWidth = windowWidth,
            Context = null
        ];

FinishLogin = (context, callbackUri, state) =>
    let
        Parts = Uri.Parts(callbackUri)[Query]
    in
        TokenMethod(Parts[code]);

TokenMethod = (code) =>

    let
        Response = Web.Contents("https://accounts.zoho.com/oauth/v2/token", [
            Content = Text.ToBinary(Uri.BuildQueryString([
                client_id = client_id,
                client_secret = client_secret,
                code = code,
                redirect_uri = redirect_uri,
                grant_type= "authorization_code"])),
            Headers=[#"Content-type" = "application/x-www-form-urlencoded",#"Accept" = "application/json"]
        ]),
        Parts = Json.Document(Response)
    in
        Parts;

//
// Common code
//

// Calls the getNextPage function until it returns null or there are errors. 
// Each call to getNextPage expects a table of data to be returned.
// The result of the previous call to getNextPage is passed along to the next call.
// Appends all pages (tables) together into a single result.
// Returns an empty table if the first call to getNextPage returns null.
Table.GenerateByPageEx = (count as nullable number, getNextPage as function) as table =>
    let
        listOfPages = List.Generate(
            () => GenerateByPageExGenerateNext(null, getNextPage, count),
            (lastPage) => lastPage[page] <> null and (count=null or lastPage[count]<=count),
            (lastPage) => GenerateByPageExGenerateNext(lastPage, getNextPage, count)
        ),
        success=
            if(List.Count(listOfPages)>0)then
                Value.Metadata(listOfPages{0}[page])[success]
            else
                true, // No data is still a success
        tableOfPages = Table.ExpandRecordColumn(Table.FromList(listOfPages, Splitter.SplitByNothing(), {"Column1"}), "Column1", {"page"}, {"Column1"}),
        firstRow = tableOfPages{0}?
    in
        if (firstRow = null) then
            Table.FromRows({}) meta[success=true]
        else
            Value.ReplaceType(
                Table.ExpandTableColumn(tableOfPages, "Column1", Table.ColumnNames(firstRow[Column1])),
                Value.Type(firstRow[Column1])
            ) meta[success=success];

GenerateByPageExGenerateNext = (lastPage as nullable record, getNextPage as function, totalCountRequested as nullable number) as record =>

    let
        lastPageTable=
            if(lastPage=null)then
                null
            else
                lastPage[page] as table,

        previousCount=
            if(lastPage=null)then
                0
            else
                lastPage[count],

        numRemaining=
            if(totalCountRequested=null)then
                null
            else
                totalCountRequested-previousCount,

        nextPageTable=
            getNextPage(lastPageTable, numRemaining),

        thisCount=Table.RowCount(nextPageTable),

        totalCount=previousCount+thisCount
    in
        [page=nextPageTable, count=totalCount];