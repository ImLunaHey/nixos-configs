let
  # Entirely local and self-contained, including styling and the illustration.
  page = status: ''
    root * ${./errors}
    rewrite * /unavailable.html
    header {
      >Cache-Control "no-store"
      >Content-Security-Policy "default-src 'none'; style-src 'unsafe-inline'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'"
      >X-Content-Type-Options "nosniff"
      >Referrer-Policy "no-referrer"
    }
    file_server {
      status ${status}
    }
  '';
  browser = ''
    method GET HEAD
    header Accept *text/html*
  '';
in {
  # Connection failures raised by Caddy itself. Other errors keep their status
  # and normal representation, including authentication/authorization failures.
  handlers = ''
    handle_errors 502 503 504 {
      @errorPageBrowser {
        ${browser}
      }
      handle @errorPageBrowser {
        ${page "{err.status_code}"}
      }
      handle {
        respond "Service temporarily unavailable" {err.status_code}
      }
    }
  '';
  # An upstream 502 response does not trigger Caddy's handle_errors. Handle
  # browser navigations here while copying API responses unchanged.
  proxy = ''
    @upstreamUnavailable status 502 503 504
    handle_response @upstreamUnavailable {
      @upstreamErrorBrowser {
        ${browser}
      }
      handle @upstreamErrorBrowser {
        ${page "{rp.status_code}"}
      }
      handle {
        copy_response
      }
    }
  '';
}
