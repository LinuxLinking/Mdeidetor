# Mdeditor

Mdeditor est un editeur Markdown pour Android, construit avec Flutter + WebView + Milkdown. Il prend en charge l'edition directe de fichiers `.md`, la gestion des fichiers recents, le changement de theme, et l'export vers PDF / DOCX / HTML.

## Fonctionnalites

- Ouvrir, editer et enregistrer des fichiers Markdown
- Acceder aux fichiers via Android SA, en conservant l'URI `content://` d'origine
- Liste des fichiers recents avec ouverture rapide
- Changement de theme, changement de theme de l'editeur, mise a l'echelle des polices
- Export vers PDF, DOCX, HTML
- Ouverture de fichiers `.md` via intent externe
- Coloration syntaxique des blocs de code (JS/TS, Python, Bash, HTML, CSS, JSON, SQL, Markdown)
- Auto-completion des crochets (`[` -> `[]`, `(` -> `()`, curseur positionne au milieu)
- Saut intelligent des caracteres fermants (taper `]` lorsque `]` suit deja le curseur saute au lieu de dupliquer)

## Conditions requises

- Flutter 3.47+
- Android 9+ (le projet cible principalement Android)

* Node.js (necessaire uniquement lors de la mise a jour des ressources frontend de `milkdown_src`)

## Executer

```bash
flutter pub get
flutter run
```

## Construire

```bash
flutter build apk --release
flutter build appbundle --release
```

## Construction des ressources frontend

Apres avoir modifie le code frontend sous `milkdown_src/`, reconstruisez les ressources de l'editeur :

```bash
cd milkdown_src
npm install
npm run build
```

La sortie est synchronisee dans `assets/web/` pour le chargement par le WebView Flutter.

## Notes

- La lecture/ecriture des fichiers est geree via Android SAF
- L'export DOCX utilise la generation OOXML cote Dart
- L'export PDF depend des capacites d'impression natives

## Journal des modifications

### 2026-08-26

**Nouvelles fonctionnalites**
- Coloration syntaxique des blocs de code : analyse syntaxique legere basee sur StreamLanguage de `@codemirror/language` pour JS/TS, Python, Bash, HTML, CSS, JSON, SQL et Markdown, sans importer l'integralite de `@codemirror/language-data` pour garder une petite taille d'APK
- Auto-completion des crochets : insertion automatique des crochets correspondants lors de la frappe de `[` ou `(`, avec le curseur positionne au milieu
- Saut intelligent des caracteres fermants : lors de la frappe de `]`, `)`, `` ` ``, `*`, etc., si le meme caractere suit deja le curseur, sauter au lieu de dupliquer

**Corrections de stabilite**
- EditorController : verification du cycle de vie `_disposed` completee pour eviter les plantages dus aux rappels asynchrones apres la suppression du WebView
- Tous les appels JS WebView enveloppes dans try-catch ; les erreurs de rendu/theme/insertion de symbole/mise en forme ne plantent plus l'application
- Pipeline de rendu natif `_drainNativeRender` : structure try-finally corrigee pour assurer le traitement de la file d'attente de rendu en attente apres les erreurs
- `_asciiEscapeJson` : correction de l'echappement pour les caracteres du plan supplementaire (emoji, etc., unite de code > 0xFFFF)
- Correction du probleme d'ordre d'affectation de `_future` lors de l'actualisation de la page d'accueil pour eviter les conditions de concurrence

**Corrections de construction**
- Configuration de build Vite : ajout du polyfill `process.env` pour corriger l'erreur prosemirror/micromark `process is not defined`

**Nouveaux modules**
- `android/render-core` : module de rendu Markdown natif (rendu incrementiel, pretraitement LaTeX/Math, mappage de decalage du curseur, etc. en Kotlin)

## Licence

Ce projet est sous licence [GNU General Public License v3.0](LICENSE).
