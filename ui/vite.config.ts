import { defineConfig } from "vite";
import { viteSingleFile } from "vite-plugin-singlefile";

export default defineConfig({
  base: "./",
  plugins: [
    {
      name: "strip-magic-help-text",
      transform(code, id) {
        if (id.includes("magic-date-picker")) {
          return code.replace(
            /p`\s*<div class="help-text">[\s\S]*?<\/div>\s*`/,
            "m", //this means to render nothing
          );
        }
      },
    },
    viteSingleFile(),
  ],
  build: {
    outDir: "dist",
    emptyOutDir: true,
    assetsInlineLimit: 100_000_000,
    cssCodeSplit: false,
  },
});
