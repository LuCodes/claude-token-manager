# Synchronisation avec claude.ai

## Avertissements de securite — a lire avant de continuer

Le mode "Synchro claude.ai" recupere tes vraies limites de forfait en appelant l'API interne de claude.ai avec ton cookie de session. Avant de l'activer, tu dois comprendre ce que ca implique :

### 1. Ton cookie donne un acces complet a ton compte

Quiconque possede ton `sessionKey` peut :
- Se connecter a claude.ai en tant que toi
- Lire toutes tes conversations (y compris les privees)
- Modifier ton abonnement ou tes parametres
- Consommer ton quota

**Ne partage JAMAIS ton cookie avec quelqu'un.** L'app le stocke dans le Keychain macOS qui est chiffre et lie a ton Mac, mais au moment ou tu l'extrais depuis DevTools, il passe par ton clipboard. Verifie qu'aucun outil de synchro clipboard (iCloud, Raycast, Paste, Alfred) ne l'envoie a un autre appareil.

### 2. Cette fonctionnalite utilise une API non-documentee

L'endpoint `/api/organizations/.../usage` est un endpoint **interne** de claude.ai, pas une API publique. Ca signifie :

- Anthropic peut changer ou bloquer cet endpoint a tout moment
- Les Terms of Service d'Anthropic interdisent l'acces automatise a l'interface web
- En theorie, ton compte pourrait etre suspendu si detecte comme bot

En pratique, aucune suspension n'a ete observee a ce jour pour ce type d'usage modere (une requete toutes les 30 secondes), mais tu utilises cette fonctionnalite **a tes risques et perils**.

### 3. L'app est open-source et sans garantie

Le code est public sur GitHub et audite par la communaute. Mais c'est un projet solo sans garantie de securite commerciale. Si tu as des doutes, inspecte le code avant d'entrer tes credentials.

### 4. Si tu soupconne une fuite

Deconnecte-toi de claude.ai depuis le site web. Ca invalide ton cookie de session immediatement, peu importe ou il se trouve. Tu peux ensuite te reconnecter normalement.

### 5. Auto-nettoyage

Si tu n'ouvres pas Claude Token Manager pendant 30 jours, tes credentials stockes sont automatiquement purges pour minimiser la fenetre d'exposition en cas de Mac vole ou compromis.

---

## Pas de risque ? Voici comment proceder

### Etape 1 : Ouvrir les DevTools sur claude.ai

1. Ouvre https://claude.ai dans Chrome, Brave ou Firefox
2. Connecte-toi a ton compte
3. Ouvre les DevTools : `Cmd + Option + I` (ou clic-droit > Inspecter)
4. Va dans l'onglet **Network**

### Etape 2 : Trouver la requete `/usage`

1. Dans claude.ai, clique sur **Settings** > **Usage** (ou va directement a https://claude.ai/settings/usage)
2. Dans l'onglet Network des DevTools, filtre par "usage"
3. Tu devrais voir une requete GET vers une URL du type :
   ```
   https://claude.ai/api/organizations/XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX/usage
   ```

### Etape 3 : Recuperer l'Organization ID

C'est la partie UUID dans l'URL ci-dessus :
```
XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX
```

Copie cette valeur et colle-la dans le champ "Organization ID" de l'app.

### Etape 4 : Recuperer le Session Key

1. Dans les DevTools, va dans l'onglet **Application** > **Cookies** > `https://claude.ai`
2. Cherche le cookie nomme `sessionKey`
3. Copie sa **valeur** (c'est une longue chaine qui commence generalement par `sk-ant-sid01-...`)
4. Colle-la dans le champ "Cookie de session" de l'app

### Etape 5 : Tester

Clique sur "Tester et enregistrer". Si tout est bon, tu verras un point vert "Connecte".

### Quand ca expire

Le cookie de session expire generalement apres quelques jours ou semaines. Quand ca arrive :
1. L'app affichera "Session claude.ai expiree" dans le dropdown
2. Reconnecte-toi a claude.ai dans ton navigateur
3. Repete les etapes 2-5 pour recoller un nouveau cookie

L'app bascule automatiquement sur les logs locaux quand le cookie expire — tu ne perds jamais l'acces a tes donnees.
