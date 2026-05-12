// Copyright (c) Microsoft Corporation.
// Licensed under the MIT License.
import { defineConfig } from "vitepress";
import { generateSidebar } from "vitepress-sidebar";
import { withMermaid } from "vitepress-plugin-mermaid";

export default withMermaid(defineConfig({
  title: "Sovereign Chat Experience Starter",
  description: "Documentation for Sovereign Chat Experience Starter",
  srcDir: "src",
  outDir: "./dist",
  base: "/",
  cleanUrls: true,
  ignoreDeadLinks: true,
  vue: {
    template: {
      compilerOptions: {
        whitespace: 'preserve'
      }
    }
  },
  themeConfig: {
    nav: [
      { text: "Home", link: "/" },
      { text: "Getting Started", link: "/1-getting-started/quickstart" },
    ],
    sidebar: generateSidebar({
      documentRootPath: "src",
      useTitleFromFileHeading: true,
      useFolderTitleFromIndexFile: true,
      useFolderLinkFromIndexFile: false,
      hyphenToSpace: true,
      underscoreToSpace: true,
      capitalizeFirst: true,
      collapsed: false,
      collapseDepth: 2,
      sortMenusByFrontmatterOrder: true,
      sortMenusOrderByDescending: false,
      excludeFilesByFrontmatterFieldName: "exclude",
      includeFolderIndexFile: false,
    }),
    socialLinks: [{ icon: "github", link: "https://github.com/Azure-Samples/foundry-azure-local-chat" }],
    search: {
      provider: "local",
    },
  },
}));
