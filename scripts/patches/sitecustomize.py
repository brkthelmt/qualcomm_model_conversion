import os
import re
import subprocess as _subprocess

def _rw(u: str) -> str:
    if not isinstance(u, str):
        return u
    u = u.replace("`", "").strip()
    u = u.replace("https://github.com/", "https://ghfast.top/github.com/")
    u = u.replace("https://raw.githubusercontent.com/", "https://ghfast.top/raw.githubusercontent.com/")
    return u

try:
    import requests as _requests
    _orig = _requests.sessions.Session.request
    def _patched(self, method, url, *args, **kwargs):
        return _orig(self, method, _rw(url), *args, **kwargs)
    _requests.sessions.Session.request = _patched
except Exception:
    pass

try:
    import urllib.request as _urllib
    _orig_urlopen = _urllib.urlopen if hasattr(_urllib, "urlopen") else _urllib.OpenerDirector.open
    def _patched_urlopen(url, *args, **kwargs):
        return _orig_urlopen(_rw(url), *args, **kwargs)
    if hasattr(_urllib, "urlopen"):
        _urllib.urlopen = _patched_urlopen
    else:
        _urllib.OpenerDirector.open = _patched_urlopen
except Exception:
    pass

try:
    import httpx as _httpx
    _orig_httpx = _httpx.Client.request
    def _patched_httpx(self, method, url, *args, **kwargs):
        return _orig_httpx(self, method, _rw(url), *args, **kwargs)
    _httpx.Client.request = _patched_httpx
except Exception:
    pass

_orig_popen = _subprocess.Popen
def _patched_popen(*args, **kwargs):
    if args and isinstance(args[0], (list, tuple)):
        a = list(args[0])
        a = [_rw(x) for x in a]
        return _orig_popen(a, *args[1:], **kwargs)
    return _orig_popen(*args, **kwargs)
_subprocess.Popen = _patched_popen
