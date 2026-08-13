import 'package:flutter/material.dart';

import '../theme/spacing.dart';

/// Legal pages served from the hosted web build at the routes `/privacy` and
/// `/terms` (hash strategy: `https://<host>/#/privacy`, `/#/terms`). AdMob,
/// the App Store, and Google Play require a reachable privacy-policy URL, so
/// this build acts as the living, always-in-sync copy of the policy.
///
/// Both pages share a common scaffold; content is plain-text based with no
/// calls to "us/we" companies because contact details live in the docs.
abstract final class LegalPages {
  LegalPages._();
}

class PrivacyPolicyPage extends StatelessWidget {
  const PrivacyPolicyPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const _LegalScaffold(
      title: 'Privacy Policy',
      updated: 'Effective date: 2026-01-01',
      sections: [
        _LegalSection(
          title: '1. Overview',
          body:
              'Docvera PDF Editor ("the app") is designed to keep your '
              'documents private. All PDF edits, annotations, merging, '
              'splitting, and sharing happen locally on your device. We do '
              'not host your files, we do not upload your documents, and we '
              'do not create accounts for you.',
        ),
        _LegalSection(
          title: '2. Local storage on mobile',
          body:
              'On Android and iOS the app stores files and recent-document '
              'metadata only in your device\'s own storage (shared '
              'preferences and app sandbox). There is no cloud backend at '
              'all. Deleting the app, its storage, or a recent entry removes '
              'that data. Anything you share or export leaves your device '
              'only through the share/export action you choose.',
        ),
        _LegalSection(
          title: '3. Local storage on the web',
          body:
              'The web build runs entirely in your browser when the app is '
              'open. It does not transmit your documents to any server and '
              'sets no tracking cookies. If you access the web build through '
              'a link that records analytics, that is controlled by the '
              'hosting provider and by the settings of your own browser, not '
              'by the app itself.',
        ),
        _LegalSection(
          title: '4. Advertising and consent',
          body:
              'The mobile versions display banner advertisements via Google '
              'AdMob. Google may show personalized or non-personalized ads '
              'depending on your consent. Before ads can be shown the app '
              'asks you for consent using Google\'s User Messaging Platform '
              '(UMP). If you do not consent, ads do not display and your '
              'experience is otherwise unaffected. Google\'s own privacy '
              'policy applies to the ad-serving side and is available at '
              'Google\'s website. The web build never loads the ad SDK.',
        ),
        _LegalSection(
          title: '5. Information we collect',
          body:
              'We collect nothing beyond what the local feature set produces '
              'for display (such as recent-document entries and file sizes), '
              'which never leave your device. Crash reports, if any were '
              'enabled, are not collected by the app. AdMob may collect '
              'standard ad identifiers and device information for the purpose '
              'of showing ads, as described in Google\'s privacy policy and '
              'the consent form you see in the app.',
        ),
        _LegalSection(
          title: '6. Data deletion and your rights',
          body:
              'Because your documents stay on your device, you may delete '
              'any file, clear recent documents, or uninstall the app '
              'entirely at any time. To withdraw ad consent, follow your '
              'device\'s advertising preferences. For any privacy question '
              'about the app, contact the developer at the email listed on '
              'the app\'s store listing.',
        ),
        _LegalSection(
          title: '7. Changes to this policy',
          body:
              'This policy may be updated from time to time. The effective '
              'date above reflects the latest revision, and the hosted '
              'version always shows the most current text.',
        ),
      ],
    );
  }
}

class TermsOfServicePage extends StatelessWidget {
  const TermsOfServicePage({super.key});

  @override
  Widget build(BuildContext context) {
    return const _LegalScaffold(
      title: 'Terms of Service',
      updated: 'Effective date: 2026-01-01',
      sections: [
        _LegalSection(
          title: '1. Acceptance',
          body:
              'By installing, accessing, or using Docvera PDF Editor you '
              'agree to these terms. If you do not agree, please do not use '
              'the app.',
        ),
        _LegalSection(
          title: '2. License',
          body:
              'The app is licensed to you for personal, non-commercial '
              'review and use. You may not reverse engineer, redistribute, '
              'or resell the app, its source, or its bundled assets except '
              'as expressly permitted.',
        ),
        _LegalSection(
          title: '3. Your documents',
          body:
              'You remain the owner of your documents. The app processes '
              'your files locally and does not store them on any servers. '
              'You are responsible for backing up your own files and for '
              'ensuring you have the right to edit each document you use '
              'with the app.',
        ),
        _LegalSection(
          title: '4. Acceptable use',
          body:
              'You agree not to use the app to violate any law, to spread '
              'malware, or to interfere with other users\' enjoyment of the '
              'service.',
        ),
        _LegalSection(
          title: '5. Advertising',
          body:
              'The mobile versions may display advertisements. Ads are '
              'optional and controlled by the consent you give; the web '
              'build is ad-free.',
        ),
        _LegalSection(
          title: '6. No warranty',
          body:
              'The app is provided "as is" without warranty of any kind, '
              'express or implied, including warranties of merchantability '
              'or fitness for a particular purpose. Editing PDFs can '
              'produce unwanted results on poorly-formed files; keep '
              'backups of anything you care about.',
        ),
        _LegalSection(
          title: '7. Limitation of liability',
          body:
              'To the maximum extent permitted by law, the developer shall '
              'not be liable for any indirect, incidental, special, or '
              'consequential damages arising from the use or inability to '
              'use the app.',
        ),
        _LegalSection(
          title: '8. Changes',
          body:
              'These terms may be updated from time to time. Continued use '
              'of the app after a change constitutes acceptance of the '
              'revised terms.',
        ),
      ],
    );
  }
}

/// Shared scaffold for a legal page: an app-bar with the document title, a
/// returned-to-home back action, and a scrollable content column.
class _LegalScaffold extends StatelessWidget {
  const _LegalScaffold({
    required this.title,
    required this.updated,
    required this.sections,
  });

  final String title;
  final String updated;
  final List<_LegalSection> sections;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        leading: BackButton(
          onPressed: () {
            final navigator = Navigator.of(context);
            if (navigator.canPop()) {
              navigator.pop();
            } else {
              navigator.pushReplacementNamed('/');
            }
          },
        ),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: ListView(
              padding: const EdgeInsets.all(AppSpacing.lg),
              children: [
                Text(
                  updated,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                ),
                const SizedBox(height: AppSpacing.lg),
                ...sections,
                const SizedBox(height: AppSpacing.xl),
                Text(
                  'Docvera PDF Editor · Docvera',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LegalSection extends StatelessWidget {
  const _LegalSection({
    required this.title,
    required this.body,
  });

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context)
                .textTheme
                .titleSmall
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            body,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  height: 1.45,
                ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Divider(height: 1, color: scheme.outlineVariant),
        ],
      ),
    );
  }
}