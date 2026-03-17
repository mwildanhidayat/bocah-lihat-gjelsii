<?php
/**
 * Protect 14 — Sidebar Hide Script
 * This script modifies admin.blade.php to hide sidebar items for non-admin users
 * Run via: php /tmp/protect14_install.php
 */

$file = '/var/www/pterodactyl/resources/views/layouts/admin.blade.php';
$content = file_get_contents($file);

if ($content === false) {
    echo "ERROR: Cannot read $file\n";
    exit(1);
}

// Already protected?
if (strpos($content, 'Protect By @WiL') !== false) {
    echo "SKIP: Already protected\n";
    exit(0);
}

// Wrap Settings sidebar item
$content = preg_replace(
    '/([ \t]*<li[^>]*>\s*<a href="{{ route\(\'admin\.settings\'\) }}".*?<\/li>)/s',
    "@if(Auth::user()->id == 1)\n$1\n@endif {{-- Protect By @WiL --}}",
    $content,
    1
);

// Wrap API sidebar item
$content = preg_replace(
    '/([ \t]*<li[^>]*>\s*<a href="{{ route\(\'admin\.api\.index\'\) ?}}".*?<\/li>)/s',
    "@if(Auth::user()->id == 1)\n$1\n@endif {{-- Protect By @WiL --}}",
    $content,
    1
);

// Wrap Databases sidebar item
$content = preg_replace(
    '/([ \t]*<li[^>]*>\s*<a href="{{ route\(\'admin\.databases\'\) }}".*?<\/li>)/s',
    "@if(Auth::user()->id == 1)\n$1\n@endif {{-- Protect By @WiL --}}",
    $content,
    1
);

// Wrap Locations sidebar item
$content = preg_replace(
    '/([ \t]*<li[^>]*>\s*<a href="{{ route\(\'admin\.locations\'\) }}".*?<\/li>)/s',
    "@if(Auth::user()->id == 1)\n$1\n@endif {{-- Protect By @WiL --}}",
    $content,
    1
);

// Wrap Nodes sidebar item
$content = preg_replace(
    '/([ \t]*<li[^>]*>\s*<a href="{{ route\(\'admin\.nodes\'\) }}".*?<\/li>)/s',
    "@if(Auth::user()->id == 1)\n$1\n@endif {{-- Protect By @WiL --}}",
    $content,
    1
);

file_put_contents($file, $content);
echo "OK: Sidebar protected\n";
