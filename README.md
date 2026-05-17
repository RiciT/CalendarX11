# CalendarX11

## How to get started?
1. Clone the repo
1. Install the npm package [@w3cj/magic-date-picker](https://www.npmjs.com/package/@w3cj/magic-date-picker) with <code>npm install @w3cj/magic-date-picker</code>, which inspired me to finally make this project
1. Inside of the ui/ directory run <code>npm run build</code>
1. Then create a .env file based on the example (if you are unsure what the names of your calendars are, run <code>gcalcli list</code>)
1. Download the [Ultralight SDK](https://ultralig.ht/download), make sure it's the 1.4.0 free version, and extract it into /deps/ultralight/
1. At this point, you might need to <code>chmod +x scripts/gcalcall.sh</code>
1. Then in the project root, run <code>zig build</code>, make sure you have Zig 0.15.1 in your PATH
1. You are done now, you just have to call zig-out/bin/zig-ultralight-x11
1. The zig-out/ directory is now entirely self-contained, so at this point, you can delete everything else and/or transfer the zig-out directory anywhere

## Dependencies
- You need Zig 0.15.1, npm, and the Ultralight SDK 1.4.0 (x64) mentioned in the first paragraph. 
- You also need to have [gcalcli](https://github.com/insanum/gcalcli) and make sure to set it up with <code>gcalcli init</code> and set up your Google Calendar API. Please read more on the gcalcli GitHub, as this application will not prompt you for it, and the Google Calendar syncing will simply fail.
- You will need the npm package [@w3cj/magic-date-picker](https://www.npmjs.com/package/@w3cj/magic-date-picker), install it with <code>npm install @w3cj/magic-date-picker</code>.
- You also need to have the X11 development headers downloaded, in particular: X11/Xlib.h, X11/Xutil.h, X11/keysym.h, these are available through most package managers.
- Finally, you will need [jq](https://github.com/jqlang/jq), a command-line JSON processor. It is available through most package managers.

## Some notes
This project was made for x64_86, and it works amazingly on it. It was not tested on other architectures, though I would not be surprised if it worked, as Zig is amazing, but no guarantees.
