<?php
/*
 * The appliance's own landing page.
 *
 * It belongs to the appliance and not to the operator's site, which is why it
 * carries the mark: docs/brand/README.md, "Do not put the mark in the footer
 * of a page the operator publishes. The appliance's own pages are ours; their
 * site is theirs. A default landing page shipped by the appliance, as LAMP
 * has, is ours and carries the mark until they replace it."
 *
 * Replacing it is the first thing a deployment does, and the page says so
 * rather than leaving the operator to guess which file it is.
 *
 * The mark is keel-lockup.svg, copied from docs/brand of the handbook and not
 * redrawn. The lockup rather than the symbol alone, because this is a page
 * that names the product to somebody seeing it for the first time.
 *
 * One sentence in it, the database location placeholder in the body below,
 * is written by conf.d/main
 * from what the image turned out to contain, so the page is true of both
 * artefacts of this recipe without being two files.
 *
 * The host comes from the request, so it is escaped before it reaches the
 * document. It is the one value on this page that somebody else chooses.
 */
$host = htmlspecialchars($_SERVER['HTTP_HOST'] ?? 'localhost', ENT_QUOTES, 'UTF-8');
?>
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>LAMP appliance</title>
<style>
:root {
  --navy: #0B2847;
  --waterline: #0072C9;
  --grey: #7F8D9D;
  --ink: #0B2847;
  --muted: #5a6875;
  --page: #ffffff;
  --card: #f5f7f9;
  --rule: #dfe5ea;
}
@media (prefers-color-scheme: dark) {
  :root {
    --ink: #eef3f7;
    --muted: #9fb0bf;
    --page: #0d1620;
    --card: #142231;
    --rule: #223347;
  }
}
* { box-sizing: border-box; }
body {
  margin: 0;
  padding: 0 16px;
  background: var(--page);
  color: var(--ink);
  font: 16px/1.6 system-ui, -apple-system, "Segoe UI", Roboto, sans-serif;
}
main { max-width: 46rem; margin: 0 auto; padding: 3rem 0 4rem; }
header { display: flex; align-items: center; gap: 1rem; margin-bottom: 2.5rem; }
header img { width: 132px; height: auto; }
h1 { font-size: 1.5rem; margin: 0 0 .25rem; letter-spacing: -.01em; }
h2 { font-size: 1rem; margin: 2.5rem 0 .75rem; text-transform: uppercase;
     letter-spacing: .08em; color: var(--muted); font-weight: 600; }
p { margin: 0 0 1rem; }
.lede { color: var(--muted); }
.rule { height: 3px; background: var(--waterline); border: 0; margin: 0 0 2rem;
        width: 4rem; border-radius: 2px; }
ul.cards { list-style: none; padding: 0; margin: 0; display: grid;
           grid-template-columns: repeat(auto-fit, minmax(13rem, 1fr)); gap: .75rem; }
ul.cards a { display: block; padding: .9rem 1rem; background: var(--card);
             border: 1px solid var(--rule); border-radius: 8px;
             text-decoration: none; color: var(--ink); }
ul.cards a:hover, ul.cards a:focus { border-color: var(--waterline); }
ul.cards strong { display: block; }
ul.cards span { color: var(--muted); font-size: .875rem; }
ul.plain { padding-left: 1.2rem; color: var(--muted); }
ul.plain a { color: inherit; }
code { background: var(--card); padding: .1rem .35rem; border-radius: 4px;
       font-size: .9em; }
footer { margin-top: 3rem; padding-top: 1.25rem; border-top: 1px solid var(--rule);
         color: var(--muted); font-size: .875rem; }
</style>
</head>
<body>
<main>
  <header>
    <img src="/keel-lockup.svg" alt="Keel Linux">
    <div>
      <h1>LAMP appliance</h1>
      <p class="lede">Apache, PHP and MariaDB on Debian 13.</p>
    </div>
  </header>
  <hr class="rule">

  <p>This server is running. Its database is @KEEL_DB_LOCATION@.</p>

  <h2>Administer it</h2>
  <ul class="cards">
    <li><a href="https://<?= $host ?>:12322/"><strong>Adminer</strong>
        <span>the database, in a browser</span></a></li>
    <li><a href="https://<?= $host ?>:12321/"><strong>Webmin</strong>
        <span>the machine, in a browser</span></a></li>
    <li><a href="https://<?= $host ?>:12320/"><strong>Web shell</strong>
        <span>a terminal, in a browser</span></a></li>
  </ul>

  <h2>Check it</h2>
  <ul class="plain">
    <li><a href="/phpinfo.php">PHP configuration</a>, which is
        <code>/var/www/phpinfo.php</code> and should be removed before this
        machine faces anyone you do not know.</li>
    <li><a href="/cgi-bin/test.cgi">CGI</a>, which proves the handler runs
        scripts under <code>/var/www/cgi-bin</code>.</li>
    <li><a href="/server-status">Apache status</a>, which
        <code>a2dismod status</code> turns off.</li>
  </ul>

  <h2>Replace this page</h2>
  <p>It is <code>/var/www/index.php</code>, and it belongs to the appliance
     rather than to your site. Your own pages carry your own marks; put them
     here and this one is gone.</p>

  <footer>
    Keel Linux, the appliance's own page. The distribution's mark on it says
    the page is the distribution's, not that your site is.
  </footer>
</main>
</body>
</html>
