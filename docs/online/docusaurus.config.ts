import { themes as prismThemes } from 'prism-react-renderer';
import type { Config } from '@docusaurus/types';
import type * as Preset from '@docusaurus/preset-classic';

// This runs in Node.js - Don't use client-side code here (browser APIs, JSX...)

const config: Config = {

  //-------------------------------------------------------------------
  // BEGIN REQUIRED FIELDS

  title: 'Export-Permission Docs',

  // Set the production url of your site here
  url: 'https://imjla.github.io',

  // Set the /<baseUrl>/ pathname under which your site is served
  // For GitHub pages deployment, it is often '/<projectName>/'
  baseUrl: '/Export-Permission/',

  // END REQUIRED FIELDS
  //-------------------------------------------------------------------




  //-------------------------------------------------------------------
  // BEGIN REQUIRED FIELDS FOR DOCUSAURUS DEPLOYMENT TO GITHUB PAGES

  // GitHub pages deployment config.
  // If you aren't using GitHub pages, you don't need these.
  organizationName: 'IMJLA', // Usually your GitHub org/user name.
  projectName: 'Export-Permission', // Usually your repo name.

  // END REQUIRED FIELDS FOR DOCUSAURUS DEPLOYMENT TO GITHUB PAGES
  //-------------------------------------------------------------------


  tagline: 'Present complex nested permissions and group memberships in a report that is easy to read',
  favicon: 'img/logo-512x512.png',

  onBrokenLinks: 'throw',
  onBrokenMarkdownLinks: 'warn',

  // Even if you don't use internationalization, you can use this field to set
  // useful metadata like html lang. For example, if your site is Chinese, you
  // may want to replace "en" with "zh-Hans".
  i18n: {
    defaultLocale: 'en',
    locales: ['en'],
  },

  presets: [
    [
      'classic',
      {
        docs: {
          sidebarPath: './sidebars.ts',
        },
        blog: false,
        theme: {
          customCss: './src/css/custom.css',
        },
      } satisfies Preset.Options,
    ],
  ],

  themeConfig: {
    // Replace with your project's social card
    image: 'img/docusaurus-social-card.jpg',
    navbar: {
      title: 'Export-Permission',
      logo: {
        alt: 'Export-Permission Logo',
        src: 'img/logo.svg',
      },
      items: [
        { to: 'docs/en-US/Export-Permission.ps1', label: 'Docs', position: 'left' }
      ],
    },
    footer: {
      style: 'dark',
      links: [
        {
          title: 'Docs',
          items: [
            {
              label: 'ReadMe',
              to: '/docs/en-US/Export-Permission.ps1',
            },
          ],
        },
        {
          title: 'Community',
          items: [
            {
              label: 'GitHub',
              href: 'https://github.com/IMJLA/Export-Permission',
            }
          ],
        }
      ],
      copyright: `Copyright © ${new Date().getFullYear()} Jeremy La Camera; Export-Permission.ps1 Online Help and Documentation Built with Docusaurus.`,
    },
    prism: {
      theme: prismThemes.github,
      darkTheme: prismThemes.dracula,
    },
  } satisfies Preset.ThemeConfig,
};

export default config;
