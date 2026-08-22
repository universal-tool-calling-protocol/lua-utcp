#!/usr/bin/env python3

from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import re


HOST = "127.0.0.1"
PORT = 8092

# Match `add` / `multiply` only when they appear as bare field names
# (not inside strings, comments, or as part of a longer identifier).
_FIELD_RE = re.compile(r"(?<![\w\"'])(add|multiply)(?![\w\"'])")


def _strip_comments(query):
    # Remove GraphQL comments (# ... to end of line) so words inside
    # comments never get treated as selected fields.
    return re.sub(r"#.*", "", query or "")


def execute_graphql(query, variables):
    variables = variables or {}

    a = variables.get("a", 0)
    b = variables.get("b", 0)

    if not isinstance(a, (int, float)) or isinstance(a, bool):
        raise ValueError("a must be a number")
    if not isinstance(b, (int, float)) or isinstance(b, bool):
        raise ValueError("b must be a number")

    cleaned = _strip_comments(query)
    fields = set(_FIELD_RE.findall(cleaned))

    data = {}

    if "add" in fields:
        data["add"] = a + b

    if "multiply" in fields:
        data["multiply"] = a * b

    if not data:
        raise ValueError(
            "query must request at least one supported field: add or multiply"
        )

    return data


class Handler(BaseHTTPRequestHandler):
    def do_POST(self):
        if self.path != "/graphql":
            self._json(404, {"errors": [{"message": "not found"}]})
            return

        try:
            length = int(self.headers.get("Content-Length", "0"))
            raw = self.rfile.read(length)

            request = json.loads(raw or b"{}")

            if not isinstance(request, dict):
                raise ValueError("request body must be a JSON object")

            query = request.get("query")
            variables = request.get("variables") or {}

            if not isinstance(variables, dict):
                raise ValueError("variables must be a JSON object")

            data = execute_graphql(query, variables)

            self._json(200, {"data": data})

        except ValueError as exc:
            self._json(400, {"errors": [{"message": str(exc)}]})

        except json.JSONDecodeError as exc:
            self._json(400, {"errors": [{"message": f"invalid JSON: {exc}"}]})

        except Exception as exc:
            self._json(500, {"errors": [{"message": str(exc)}]})

    def _json(self, status, value):
        body = json.dumps(value).encode("utf-8")

        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()

        try:
            self.wfile.write(body)
        except BrokenPipeError:
            pass

    def log_message(self, *_args):
        pass


if __name__ == "__main__":
    print(f"GraphQL server listening on http://{HOST}:{PORT}/graphql")

    ThreadingHTTPServer((HOST, PORT), Handler).serve_forever()
