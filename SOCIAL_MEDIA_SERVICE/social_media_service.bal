import ballerina/http;
import ballerina/time;

type User record {|
    readonly int id;
    string name;
    time:Date birthDate;
    string mobileNumber;
|};

table<User> key(id) users = table [
    {id:1, name:"Joe", birthDate: {year:1990, month:2, day:3}, mobileNumber:"0718923456"}
];

service /social\-media on new http:Listener(9090) {

    // social-media/users

    resource function get users() returns User[]|error{
        return users.toArray();
    }
}

