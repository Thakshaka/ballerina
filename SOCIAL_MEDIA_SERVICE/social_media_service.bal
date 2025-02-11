import ballerina/http;
import ballerina/sql;
import ballerina/time;
import ballerinax/mysql;
import ballerinax/mysql.driver as _;
import ballerina/lang.regexp;

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
    {id: 1, name: "Joe", birthDate: {year: 1990, month: 2, day: 3}, mobileNumber: "0718923456"}
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

type DatabaseConfig record {|
    string host;
    string user;
    string password;
    string database;
    int port;
|};

// post representations
type Post record {|
    int id;
    string description;
    string tags;
    string category;
    @sql:Column {name: "created_date"}
    time:Date created_date;
|};

configurable DatabaseConfig databaseConfig = ?;

mysql:Client socialMediaDb = check new (...databaseConfig);

service /social\-media on new http:Listener(9090) {

    // social-media/users

    // get users
    resource function get users() returns User[]|error {
        stream<User, sql:Error?> userStream = socialMediaDb->query(`SELECT * FROM users`);
        return from var user in userStream
            select user;
    }

    // get a user
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

    // create a user
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
                // rollback;
            }
        }
        return http:CREATED;
    }

    resource function get users/[int id]/posts() returns PostWithMeta[]|UserNotFound|error {
        User|error result = socialMediaDb->queryRow(`SELECT * FROM users WHERE id = ${id}`);
        if result is sql:NoRowsError {
            ErrorDetails errorDetails = buildErrorPayload(string `id: ${id}`, string `users/${id}/posts`);
            UserNotFound userNotFound = {
                body: errorDetails
            };
            return userNotFound;
        }

        stream<Post, sql:Error?> postStream = socialMediaDb->query(`SELECT id, description, category, created_date, tags FROM posts WHERE user_id = ${id}`);
        Post[]|error posts = from Post post in postStream
            select post;
        return postToPostWithMeta(check posts);
    }
}

function buildErrorPayload(string msg, string path) returns ErrorDetails => {
    message: msg,
    timeStamp: time:utcNow(),
    details: string `uri=${path}`
};

type Created_date record {
    int year;
    int month;
    int day;
};

type Meta record {
    string[] tags;
    string category;
    Created_date created_date;
};

type PostWithMeta record {
    int id;
    string description;
    Meta meta;
};

function postToPostWithMeta(Post[] post) returns PostWithMeta[] => from var postItem in post
    select {
        id: postItem.id,
        description: postItem.description,
        meta: {
            tags: regexp:split(re `,`, postItem.tags),
            category: postItem.category,
            created_date: postItem.created_date
        }
    };
