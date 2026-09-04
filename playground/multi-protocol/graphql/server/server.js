// Poste GraphQL test server — a real GraphQL engine (graphql-js) on plain
// node:http, so manual GRAPHQL requests exercise actual query parsing,
// variables, and the {data}/{errors} response envelope.
//
// Endpoints:
//   POST /            GraphQL over HTTP (JSON body, or application/graphql)
//   GET  /?query=...  Convenience GET for quick curl checks
//   GET  /health      Health check
//
// Schema highlights for manual testing:
//   { hello }                          — trivial scalar query
//   user(id: "1") { id name email }    — variables + object fields
//   mutation { add(a: 19, b: 23) }     — mutation
//   { nonexistent }                    — GraphQL validation errors array

const http = require('http');
const { graphql, buildSchema } = require('graphql');

const schema = buildSchema(`
  type Query {
    hello(name: String! = "world"): String!
    user(id: ID!): User
  }
  type User {
    id: ID!
    name: String!
    email: String!
  }
  type Mutation {
    add(a: Int!, b: Int!): Int!
  }
`);

const users = {
  1: { id: '1', name: 'Ada Lovelace', email: 'ada@example.com' },
  2: { id: '2', name: 'Alan Turing', email: 'alan@example.com' },
};

const root = {
  hello: ({ name }) => `Hello, ${name}!`,
  user: ({ id }) => users[String(id)] || null,
  add: ({ a, b }) => a + b,
};

function respond(res, payload) {
  const body = JSON.stringify(payload);
  res.writeHead(200, { 'Content-Type': 'application/json' });
  res.end(body);
}

function run(res, query, variables, operationName) {
  graphql({ schema, source: query, rootValue: root, variableValues: variables, operationName })
    .then((result) => respond(res, result))
    .catch((err) => respond(res, { errors: [{ message: err.message }] }));
}

const server = http.createServer((req, res) => {
  if (req.method === 'GET') {
    const url = new URL(req.url, 'http://localhost');
    if (url.pathname === '/health') return respond(res, { status: 'ok' });
    const query = url.searchParams.get('query');
    if (!query) return respond(res, { errors: [{ message: 'missing ?query=' }] });
    let variables;
    const rawVariables = url.searchParams.get('variables');
    if (rawVariables) variables = JSON.parse(rawVariables);
    return run(res, query, variables);
  }
  if (req.method !== 'POST') {
    return respond(res, { errors: [{ message: 'use POST' }] });
  }

  const chunks = [];
  req.on('data', (c) => chunks.push(c));
  req.on('end', () => {
    const raw = Buffer.concat(chunks).toString('utf8');
    const contentType = (req.headers['content-type'] || '').split(';')[0].trim();
    let query;
    let variables;
    let operationName;
    if (contentType === 'application/graphql') {
      query = raw;
    } else {
      try {
        const parsed = JSON.parse(raw || '{}');
        query = parsed.query;
        variables = parsed.variables;
        operationName = parsed.operationName;
      } catch (err) {
        return respond(res, { errors: [{ message: 'invalid JSON body: ' + err.message }] });
      }
    }
    if (!query) return respond(res, { errors: [{ message: 'missing "query" in body' }] });
    run(res, query, variables, operationName);
  });
});

const port = process.env.POSTE_GRAPHQL_PORT || 8890;
server.listen(port, '0.0.0.0', () => {
  console.log(`poste-graphql listening on :${port}`);
});
