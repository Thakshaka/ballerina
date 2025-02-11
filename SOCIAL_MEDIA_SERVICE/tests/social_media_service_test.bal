import ballerinax/mysql;
import ballerina/http;
import ballerina/test;

@test:Mock {
    functionName: "initSocialMediaDb"
}
function initMockSocialMediaDb() returns mysql:Client|error => test:mock(mysql:Client);

@test:Config{}
function testUsersById() returns error? {
    User userExpected = {id: 1, name: "Joe", birthDate: {year: 1990, month: 2, day: 3}, mobileNumber: "0718923456"};
    test:prepare(socialMediaDb).when("queryRow").thenReturn(userExpected);

    http:Client socialMediaEndpoint = check new("localhost:9090/social-media");
    User userActual = check socialMediaEndpoint->/users/[userExpected.id.toString()];

    test:assertEquals(userActual, userExpected);
}