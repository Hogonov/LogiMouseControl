# Third-party acknowledgements

## OpenLogi

https://github.com/AprilNEA/OpenLogi
Reference revision: a92aa43bed3732be5f7fde7aed2fc12cc48ba001.

HID++ feature layouts, control IDs, SmartShift semantics, and haptic commands
were adapted to Swift from OpenLogi and its openlogi-hidpp crate. Device colour
selection and image-hotspot coordinate conventions also follow OpenLogi. This app does
not embed OpenLogi, its UI, updater, or network services.

OpenLogi is offered under MIT or Apache-2.0. The MIT option is used here:

MIT License

Copyright (c) 2026 AprilNEA

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

## openlogi-hidpp

BSD Zero Clause License

Copyright (c) 2025 Lukas Schulte Pelkum

Permission to use, copy, modify, and/or distribute this software for any
purpose with or without fee is hereby granted.

THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES WITH
REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF MERCHANTABILITY
AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY SPECIAL, DIRECT,
INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES WHATSOEVER RESULTING FROM
LOSS OF USE, DATA OR PROFITS, WHETHER IN AN ACTION OF CONTRACT, NEGLIGENCE OR
OTHER TORTIOUS ACTION, ARISING OUT OF OR IN CONNECTION WITH THE USE OR
PERFORMANCE OF THIS SOFTWARE.

## Mac Mouse Fix

https://github.com/noah-nuebling/mac-mouse-fix
Reference revision: 8538a5cadcd3afc30d4bce090d80fda63af49fe6.

Mac Mouse Fix was studied as a behavioral reference for smooth scrolling.
Its source is under the custom MMF License. No MMF source files, assets,
algorithms, private API bridges, monetization or update components are copied
into this application. The time-based exponential scroll integrator is an
independent implementation using public CoreGraphics events.

## MX Master 4 product images and metadata

The product renders (`front_*.png`, `side_*.png`), `manifest.json`, and
`core_metadata.json` in `Sources/LogiMouseControl/DeviceImages` were obtained from:
https://assets.openlogi.org/v1/devices/mx_master_4/

These are Logitech product assets mirrored by the OpenLogi asset service, not
original artwork of this project. The OpenLogi source-code MIT license above
is not a license grant for Logitech's product artwork or trademarks.
Only the front/side renders and their catalog/marker metadata are bundled;
no OpenLogi brand artwork is included. Source SHA-256 hashes are recorded in
`Resources/DeviceImagesProvenance.json`.

## Trademarks

Logitech, Logi, MX Master and MagSpeed belong to their respective owners.
This independent application is not affiliated with or endorsed by Logitech.
