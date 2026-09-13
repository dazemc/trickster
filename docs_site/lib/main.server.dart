/// The entrypoint for the **server** environment.
///
/// The [main] method will only be executed on the server during pre-rendering.
/// To run code on the client, check the `main.client.dart` file.
library;

// Server-specific Jaspr import.
import 'package:jaspr/server.dart';

import 'package:jaspr_content/components/callout.dart';
import 'package:jaspr_content/components/github_button.dart';
import 'package:jaspr_content/components/header.dart';
import 'package:jaspr_content/components/image.dart';
import 'package:jaspr_content/components/sidebar.dart';
import 'package:jaspr_content/components/theme_toggle.dart';
import 'package:jaspr_content/jaspr_content.dart';
import 'package:jaspr_content/theme.dart';

import 'main.server.options.dart';

void main() {
  // Initializes the server environment with the generated default options.
  Jaspr.initializeApp(
    options: defaultServerOptions,
  );

  // Starts the app.
  //
  // [ContentApp] spins up the content rendering pipeline from jaspr_content to render
  // your markdown files in the content/ directory to a beautiful documentation site.
  runApp(
    ContentApp(
      // Enables mustache templating inside the markdown files.
      templateEngine: MustacheTemplateEngine(),
      parsers: [
        MarkdownParser(),
      ],
      extensions: [
        // Adds heading anchors to each heading.
        HeadingAnchorsExtension(),
        // Generates a table of contents for each page.
        TableOfContentsExtension(),
      ],
      components: [
        // The <Info> block and other callouts.
        Callout(),
        // NOTE: jaspr_content's CodeBlock is intentionally off. Its
        // highlighter only ships a Dart grammar and null-crashes on any
        // other fence language (sh, json, text). Plain fenced blocks
        // render unhighlighted instead. Re-enable if that is fixed
        // upstream or custom grammars are registered.
        // Adds zooming and caption support to images.
        Image(zoom: true),
      ],
      layouts: [
        // Out-of-the-box layout for documentation sites.
        DocsLayout(
          header: Header(
            title: 'Trickster Bar',
            logo: '/images/logo.svg',
            items: [
              // Enables switching between light and dark mode.
              ThemeToggle(),
              // Shows github stats.
              GitHubButton(repo: 'dazemc/trickster-bar'),
            ],
          ),
          sidebar: Sidebar(
            groups: [
              // Adds navigation links to the sidebar.
              SidebarGroup(
                links: [
                  SidebarLink(text: "Overview", href: '/'),
                  SidebarLink(text: "Installation", href: '/installation'),
                  SidebarLink(text: "Status", href: '/status'),
                ],
              ),
              SidebarGroup(
                title: 'Using',
                links: [
                  SidebarLink(text: "Configuration", href: '/configuration'),
                  SidebarLink(text: "Modules", href: '/modules'),
                  SidebarLink(text: "CLI reference", href: '/cli'),
                ],
              ),
              SidebarGroup(
                title: 'Internals',
                links: [
                  SidebarLink(text: "Architecture", href: '/architecture'),
                  SidebarLink(text: "Development", href: '/development'),
                ],
              ),
            ],
          ),
        ),
      ],
      theme: ContentTheme(
        // Denial brand accent, light and dark variants.
        primary: ThemeColor(ThemeColors.violet.$500, dark: ThemeColors.violet.$300),
        background: ThemeColor(ThemeColors.slate.$50, dark: ThemeColors.zinc.$950),
        colors: [
          ContentColors.quoteBorders.apply(ThemeColors.violet.$400),
        ],
      ),
    ),
  );
}
