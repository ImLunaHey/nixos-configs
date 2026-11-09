#!/usr/bin/env python3
"""Check the deployed home's unauthenticated boundary without using credentials."""

import urllib.error
import urllib.parse
import urllib.request


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, *args, **kwargs):
        return None


def main():
    opener = urllib.request.build_opener(NoRedirect)

    def check(path, expected, headers=None):
        request = urllib.request.Request(
            "https://flaked.org" + path, headers=headers or {}
        )
        try:
            response = opener.open(request, timeout=20)
        except urllib.error.HTTPError as error:
            response = error
        with response:
            body = response.read().decode(errors="replace")
            if response.status not in expected:
                raise RuntimeError(f"{path}: unexpected HTTP {response.status}")
            if "https://romm.flaked.org/" in body or "https://jellyfin.flaked.org/" in body:
                raise RuntimeError(f"{path}: service links disclosed without login")
            print(f"PASS {path}: HTTP {response.status}")
            return response.headers

    check("/", {200})
    for path in ("/services", "/services/"):
        check(path, {401})
    for path in ("/services.html", "/portal/services.html", "/%2e%2e/portal/services.html"):
        check(path, {400, 404})
    for headers in (
        {"X-Auth-Request-User": "luna", "X-Auth-Request-Groups": "home-users"},
        {"Cookie": "__Host-flaked_session=forged"},
        {"X-Forwarded-For": "127.0.0.1", "X-Real-IP": "127.0.0.1"},
    ):
        check("/services", {401}, headers)

    headers = check("/oauth2/start?rd=%2Fservices", {302})
    location = urllib.parse.urlsplit(headers.get("Location", ""))
    query = urllib.parse.parse_qs(location.query)
    if not (
        location.scheme == "https"
        and location.hostname == "id.flaked.org"
        and query.get("redirect_uri") == ["https://flaked.org/oauth2/callback"]
        and query.get("code_challenge_method") == ["S256"]
        and query.get("code_challenge")
        and query.get("state")
        and query.get("nonce")
    ):
        raise RuntimeError("Pocket ID authorization redirect is incomplete or incorrect")
    print("PASS Pocket ID redirect, PKCE, state and nonce (values withheld)")


if __name__ == "__main__":
    main()
