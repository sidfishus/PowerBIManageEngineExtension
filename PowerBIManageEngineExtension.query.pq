// Use this file to write queries to test your data connector

// Get 11 requests starting from position '127900'.
// let
//     webResult = ManageEngineConnector.GetMultiple("https://sdpondemand.manageengine.com/api/v3/requests", null, null, null, 11, 127900),
//     success=Value.Metadata(webResult)[success],
//     requestsExpanded1 =
//         if(success)then
//             Table.ExpandRecordColumn(webResult, "Value", {"display_id" /* This is OUR ticket number */, "id" /* ME internal ID */, "subject", "requester"})
//         else
//             null,
//     output =
//         if(success)then
//             Table.ExpandRecordColumn(requestsExpanded1, "requester", {"email_id"})
//         else
//             webResult
// in
//     output

let
    searchCriteria=
        "[
            {
                ""field"": ""status.in_progress"",
                ""condition"": ""is"",
                ""logical_operator"": ""and"",
                ""values"": [
                  true
                ]
            }
        ]",
    fieldsRequested={
        "display_id",
        "id",
        "subject",
        {
            "requester",
            "email_id",
            {
                "department",
                "name"
            }
        },
        "description"
     },
    webResult = ManageEngineConnector.GetMultiple("https://sdpondemand.manageengine.com/api/v3/requests", fieldsRequested, searchCriteria, "subject", "asc", 10)
in
    webResult
// 

// let
//     fieldsRequested={
//         "display_id",
//         "id",
//         "subject",
//         {
//             "requester",
//             "email_id",
//             {
//                 "department",
//                 "name"
//             }
//         },
//         "description"
//      },
//     webResult = ManageEngineConnector.GetSingle("https://sdpondemand.manageengine.com/api/v3/requests/" & "10235000053116436", fieldsRequested)
// in
//     webResult