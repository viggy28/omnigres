CREATE TABLE users (
    id integer PRIMARY KEY GENERATED ALWAYS AS IDENTITY,
    handle text,
    name text
);

INSERT INTO users (handle, name) VALUES ('johndoe', 'John');

INSERT INTO omni_httpd.listeners (listen, query) VALUES (array[row('127.0.0.1', 9000)::omni_httpd.listenaddress], $$
SELECT omni_httpd.http_response(headers => array[omni_httpd.http_header('content-type', 'text/html')], body => 'Hello, <b>' || users.name || '</b>!'), 1 AS priority
       FROM request
       INNER JOIN users ON string_to_array(request.path,'/', '') = array[NULL, 'users', users.handle]
UNION
SELECT omni_httpd.http_response(body => request.headers::text), 1 AS priority FROM request WHERE request.path = '/headers'
UNION
SELECT omni_httpd.http_response(body => request.body), 1 AS priority FROM request WHERE request.path = '/echo'
UNION
SELECT omni_httpd.http_response(status => 404, body => json_build_object('method', request.method, 'path', request.path, 'query_string', request.query_string)), 0 AS priority
       FROM request
ORDER BY priority DESC
$$);

-- Now, the actual tests

-- FIXME: for the time being, since there's no "request" extension yet, we're shelling out to curl

\! curl --retry-connrefused --retry 10  --retry-max-time 10 --silent -w '\n%{response_code}\nContent-Type: %header{content-type}\n\n' http://localhost:9000/test?q=1

\! curl --retry-connrefused --retry 10  --retry-max-time 10 --silent -w '\n%{response_code}\nContent-Type: %header{content-type}\n\n' -d 'hello world' http://localhost:9000/echo

\! curl --retry-connrefused --retry 10  --retry-max-time 10 --silent -w '\n%{response_code}\nContent-Type: %header{content-type}\n\n' http://localhost:9000/users/johndoe

\! curl --retry-connrefused --retry 10  --retry-max-time 10 --silent -A test-agent http://localhost:9000/headers

-- Try changing configuration

UPDATE omni_httpd.listeners SET listen = array[row('127.0.0.1', 9001)::omni_httpd.listenaddress,
                                               row('127.0.0.1', 9002)::omni_httpd.listenaddress
];

\! curl --retry-connrefused --retry 10  --retry-max-time 10 --silent -w '\n%{response_code}\nContent-Type: %header{content-type}\n\n' http://localhost:9001/test?q=1

\! curl --retry-connrefused --retry 10  --retry-max-time 10 --silent -w '\n%{response_code}\nContent-Type: %header{content-type}\n\n' http://localhost:9002/test?q=1

\! curl --silent -w '%{exitcode}\n' http://localhost:9000/test?q=1

INSERT INTO omni_httpd.listeners (listen, query) VALUES (array[row('127.0.0.1', 9001)::omni_httpd.listenaddress], $$
SELECT omni_httpd.http_response(body => 'another port') FROM request
$$);

-- Ensure we serve correct query for a different listener
\! curl --retry-connrefused --retry 10 --retry-max-time 10 --silent http://localhost:9001