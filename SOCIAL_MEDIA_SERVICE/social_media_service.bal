import ballerina/http;
import ballerina/time;
import ballerina/sql;
import ballerinax/mysql;
import ballerinax/mysql.driver as _;

type User record {|
    readonly int id;
    string name;
    @sql:Column {name: "birth_date"}
    time:Date birthDate;

    @sql:Column {name: "mobile_number"}
    string mobileNumber;
|};

type NewUser record {|
    string name;
    time:Date birthDate;
    string mobileNumber;
|};

table<User> key(id) users = table [
    {id:1, name:"Joe", birthDate: {year:1990, month:2, day:3}, mobileNumber:"0718923456"}
];

type ErrorDetails record {
    string message;
    string details;
    time:Utc timeStamp;
};

type UserNotFound record {|
    *http:NotFound;
    ErrorDetails body;
|};

mysql:Client socialMediaDb = check new("localhost", "username", "password", "social_media_database", 3306);

service /social\-media on new http:Listener(9090) {

    // social-media/users

    resource function get users() returns User[]|error{
        stream<User, sql:Error?> userStream = socialMediaDb->query(`SELECT * FROM users`);
        return from var user in userStream select user;
    }

    resource function get users/[int id]() returns User|UserNotFound|error {
        User|sql:Error user = socialMediaDb->queryRow(`SELECT * FROM users WHERE id = ${id}`);
        if user is sql:NoRowsError {
            UserNotFound userNotFound = {
                body: {
                    message: string `id: ${id}`,
                    details: string `user/${id}`,
                    timeStamp: time:utcNow()
                }
            };
            return userNotFound;
        }
        return user;
    }

    resource function post users(NewUser newUser) returns http:Created|error {
        transaction {
            _ = check socialMediaDb->execute(`
            INSERT INTO users (birth_date, name, mobile_number)
            VALUES (${newUser.birthDate}, ${newUser.name}, ${newUser.mobileNumber});`);

            _ = check socialMediaDb->execute(`
                INSERT INTO followers (birth_date, name, mobile_number)
                VALUES (${newUser.birthDate}, ${newUser.name}, ${newUser.mobileNumber});`);

            if true {
                 check commit;
            } else {
                rollback;
            }
        }
        return http:CREATED;
    }
}

