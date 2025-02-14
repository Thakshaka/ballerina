import ballerina/http;
import ballerina/sql;
import ballerina/time;
import ballerinax/mysql;
import ballerinax/mysql.driver as _;
import ballerina/lang.regexp;
// import ballerinax/slack;
// import balguides/sentiment.analysis;
import ballerina/constraint;
import ballerina/log;

type User record {|
    readonly int id;
    string name;
    @sql:Column {name: "birth_date"}
    time:Date birthDate;

    @sql:Column {name: "mobile_number"}
    string mobileNumber;
|};

type NewUser record {|

    @constraint:String {
        minLength: 2,
        maxLength: 100
    }
    string name;
    time:Date birthDate;

    @constraint:String {
        pattern: re `^(\+94|0)[0-9]{9}`
    }
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

final mysql:Client socialMediaDb = check initSocialMediaDb();

function initSocialMediaDb() returns mysql:Client|error => check new(...databaseConfig);

configurable http:RetryConfig retryConfig = ?;
http:Client sentimentEndpoint = check new("https://localhost:9099/text-processing",
    timeout = 30,
    retryConfig = {...retryConfig},
    secureSocket = {
        cert: "./resources/public.crt"
    },
    auth = {
        tokenUrl: "https://localhost:9445/oauth2/token",
        clientId: "FlfJYKBD2c925h4lkycqNZlC2l4a",
        clientSecret: "PJz0UhTJMrHOo68QQNpvnqAY_3Aa",
        scopes: "admin",
        clientConfig: {
            secureSocket: {
                cert: "./resources/public.crt"
            }
        }
    }
);

// analysis:Client sentimentAnalysisClient = check new({
//     timeout: 30
// });

// type SlackConfig record {|
//     string authToken;
//     string channelName;
// |};

// configurable SlackConfig slackConfig = ?;

// slack:Client slackClient = check new({
//     auth: {
//         token: slackConfig.authToken
//     }
// });

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

            // _ = check socialMediaDb->execute(`
            //     INSERT INTO followers (birth_date, name, mobile_number)
            //     VALUES (${newUser.birthDate}, ${newUser.name}, ${newUser.mobileNumber});`);

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

    resource function post users/[int id]/posts(NewPost newPost) returns http:Created|UserNotFound|PostForbidden|error {
        do {
            _ = check socialMediaDb->queryRow(`SELECT * FROM users WHERE id = ${id}`, returnType = User);

            // analysis:Sentiment sentiment = check sentimentAnalysisClient->/api/sentiment.post({text: newPost.description});
            Sentiment sentiment = check sentimentEndpoint->/api/sentiment.post({text: newPost.description});
            if sentiment.label == "neg" {
                PostForbidden postForbidden = { body: {message: string `id: ${id}`, details: string `users/${id}/posts`, timeStamp: time:utcNow()}};
                return postForbidden;
            }
            
            _ = check socialMediaDb->execute(`
                INSERT INTO posts(description, category, created_date, tags, user_id)
                VALUES (${newPost.description}, ${newPost.category}, CURDATE(), ${newPost.tags}, ${id});`);

            // _  = check slackClient->/chat\.postMessage.post({
            //     channel: slackConfig.channelName,
            //     text: string `User ${user.name} has a new post.`
            //   });
            return http:CREATED;
        } on fail var user {
            if user is sql:NoRowsError {
                ErrorDetails errorDetails = buildErrorPayload(string `id: ${id}`, string `users/${id}/posts`);
                UserNotFound userNotFound = {
                    body: errorDetails
                };
                return userNotFound;
            }
            if user is error {
                log:printError("Some error", 'error = user);
                return user;
            }
        }
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

public type NewPost record {|
    string description;
    string tags;
    string category;
|};

type PostForbidden record {|
    *http:Forbidden;
    ErrorDetails body;
|};

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

type Probability record {
    decimal neg;
    decimal neutral;
    decimal pos;
};

type Sentiment record {
    Probability probability;
    string label;
};

