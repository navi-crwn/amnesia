#!/usr/bin/env python3
"""Builds docs/intro.html (GitHub Pages) from site/intro.body.html.
The body file is the single source; it is also what gets previewed as an Artifact."""
import os
here = os.path.dirname(os.path.abspath(__file__))
body = open(os.path.join(here, "intro.body.html"), encoding="utf-8").read()
head = """<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
<meta name="description" content="Your Mac forgets everything at every logout, except the logins and files you choose to keep. Free and open source.">
<meta property="og:title" content="Amnesia for Mac">
<meta property="og:description" content="Your Mac forgets everything, except what you choose.">
<meta property="og:image" content="banner.png">
<link rel="icon" href="logo.png">
"""
i = body.index("<style>")
out = head + body[:i] + "</head>\n<body>\n" + body[i:] + "\n</body>\n</html>\n"
open(os.path.join(here, "..", "docs", "intro.html"), "w", encoding="utf-8").write(out)
print("docs/intro.html written")
