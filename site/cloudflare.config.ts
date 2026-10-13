import { bindings, defineConfig } from "cf/config";

export default defineConfig({
	worker: {
		name: "agry-site",
		compatibilityDate: "2026-10-01",
		entrypoint: "./src/index.js",
		env: {
			ASSETS: bindings.assets(),
		},
		// Every request goes through the Worker so it can redirect www.
		assets: {
			runWorkerFirst: true,
		},
		domains: [
			"agry.dev",
			"www.agry.dev",
		],
	},
});
