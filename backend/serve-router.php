<?php
// Dev-only router for `php -S` (e2e). PHP's built-in server does not apply
// -t reliably on Windows here, so this router serves real files from public/
// and hands everything else to Laravel's front controller.
$public = __DIR__ . '/public';
$uri = urldecode(parse_url($_SERVER['REQUEST_URI'], PHP_URL_PATH) ?? '/');
if ($uri !== '/' && is_file($public . $uri)) {
    return false;
}
$_SERVER['SCRIPT_NAME'] = '/index.php';
$_SERVER['SCRIPT_FILENAME'] = $public . '/index.php';
require_once $public . '/index.php';
