# purge.vcl -- Cache Purge Library for Varnish

# Regex purging
# Treat the request URL as a regular expression.
sub purge_regex {
    ban("obj.http.X-VC-Req-URL ~ " + req.url + " && obj.http.X-VC-Req-Host == " + req.http.host);
}

# Exact purging
# Use the exact request URL (including any query params)
sub purge_exact {
    ban("obj.http.X-VC-Req-URL == " + req.url + " && obj.http.X-VC-Req-Host == " + req.http.host);
}

# Page purging (default)
# Use the exact request URL, but ignore any query params
sub purge_page {
    set req.url = regsub(req.url, "\?.*$", "");
    ban("obj.http.X-VC-Req-URL-Base == " + req.url + " && obj.http.X-VC-Req-Host == " + req.http.host);
}

# The purge behavior can be controlled with the X-VC-Purge-Method header.
#
# Setting the X-VC-Purge-Method header to contain "regex" or "exact" will use
# those respective behaviors.  Any other value for the X-Purge header will
# use the default ("page") behavior.
#
# The X-VC-Purge-Method header is not case-sensitive.
#
# If no X-VC-Purge-Method header is set, the request url is inspected to attempt
# a best guess as to what purge behavior is expected.  This should work for
# most cases, although if you want to guarantee some behavior you should
# always set the X-VC-Purge-Method header.

sub vcl_recv {
    if (req.request == "PURGE") {
        if (req.http.X-VC-Purge-Key == "ff93c3cb929cee86901c7eefc8088e9511c005492c6502a930360c02221cf8f4") {
            set req.http.X-VC-Purge-Key-Auth = "true";
        } else {
            set req.http.X-VC-Purge-Key-Auth = "false";
        }
        if (client.ip !~ purge && req.http.X-VC-Purge-Key-Auth != "true") {
            error 405 "Not allowed from " + client.ip;
        }

        if (req.http.X-VC-Purge-Method) {
            if (req.http.X-VC-Purge-Method ~ "(?i)regex") {
                call purge_regex;
            } elsif (req.http.X-VC-Purge-Method ~ "(?i)exact") {
                call purge_exact;
            } else {
                call purge_page;
            }
        } else {
            # No X-Purge-Method header was specified.
            # Do our best to figure out which one they want.
            if (req.url ~ "\.\*" || req.url ~ "^\^" || req.url ~ "\$$" || req.url ~ "\\[.?*+^$|()]") {
                call purge_regex;
            } elsif (req.url ~ "\?") {
                call purge_exact;
            } else {
                call purge_page;
            }
        }
        error 200 "Purged " + req.url + " " + req.http.host;
    }
}

sub vcl_fetch {
    set beresp.http.X-VC-Req-Host = req.http.host;
    set beresp.http.X-VC-Req-URL = req.url;
    set beresp.http.X-VC-Req-URL-Base = regsub(req.url, "\?.*$", "");
}

sub vcl_deliver {
    unset resp.http.X-VC-Req-Host;
    unset resp.http.X-VC-Req-URL;
    unset resp.http.X-VC-Req-URL-Base;

    if (obj.hits > 0) {
        set resp.http.X-VC-Cache = "HIT";
    } else {
        set resp.http.X-VC-Cache = "MISS";
    }

    if (resp.http.X-VC-Debug ~ "true") {
        set resp.http.X-VC-Hash = req.url+"#"+req.http.host;
    } else {
        unset resp.http.X-VC-Enabled;
        unset resp.http.X-VC-Cache;
        unset resp.http.X-VC-Debug;
        unset resp.http.X-VC-Cacheable;
        unset resp.http.X-VC-Purge-Key-Auth;
        unset resp.http.X-VC-TTL;
        unset resp.http.X-VC-GotSession;
    }
}
