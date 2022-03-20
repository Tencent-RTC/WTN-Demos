const path = require("path");
const { defineConfig } = require("vite");

module.exports = defineConfig({
  build: {
    lib: {
      entry: path.resolve(__dirname, "src/index.ts"),
      name: "wtnclient",
      fileName: (format) => `wtnclient.${format}.js`,
    },
    rollupOptions: {
      output: {
        globals: {},
      },
    },
  },
});
