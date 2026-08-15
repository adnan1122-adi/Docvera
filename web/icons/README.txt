WEB ICON PACKAGE
================

favicon.ico
Contains 16x16, 32x32 and 48x48 favicon sizes.

favicon-16x16.png
16x16 favicon.

favicon-32x32.png
32x32 favicon.

favicon-48x48.png
48x48 favicon.

apple-touch-icon.png
180x180 Apple Touch Icon.

icon-192.png
192x192 PWA icon.

icon-512.png
512x512 PWA icon.

manifest.webmanifest
Web App Manifest.

HOW TO USE
----------
Place all the generated files in your website's public or static root directory (e.g. /public or /static).

In the <head> section of your HTML, add:

  <link rel="icon" href="/favicon.ico" sizes="any">
  <link rel="icon" type="image/png" sizes="32x32" href="/favicon-32x32.png">
  <link rel="icon" type="image/png" sizes="16x16" href="/favicon-16x16.png">
  <link rel="apple-touch-icon" href="/apple-touch-icon.png">
  <link rel="manifest" href="/manifest.webmanifest">
