import { defineConfig } from "cf/config";

export default defineConfig({
	worker: {
		name: "agry-site",
		compatibilityDate: "2026-10-01",
		domains: [
			"agry.dev",
			"www.agry.dev",
		],
	},
});
