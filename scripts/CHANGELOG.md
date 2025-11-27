# Changelog - Scripts de Sauvegarde VPS

## Version 1.1 - 2025-11-27

### 🐛 Correction Critique - Script de Restauration

**Problème identifié :**
- La restauration des bases de données ne fonctionnait pas correctement
- Les tables n'étaient pas restaurées même si le script indiquait un succès
- Cause : Le script ne supprimait pas la base existante avant restauration

**Modifications apportées au script `restore.sh` :**

1. ✅ **Suppression de la base existante avant restauration**
   - Ajout d'un `DROP DATABASE` avant la création
   - Garantit une restauration propre sans conflit de données
   - Message de log explicite : "suppression pour restauration complète"

2. ✅ **Amélioration de la gestion des erreurs**
   - Utilisation d'un fichier temporaire pour capturer les erreurs MySQL
   - Code de retour explicite (`RESTORE_STATUS`)
   - Meilleure gestion du pipeline `gunzip | mysql`
   - Affichage du code d'erreur en cas d'échec

3. ✅ **Meilleur logging**
   - Ajout du message "Import des données dans [base]..."
   - Les erreurs MySQL sont maintenant écrites dans le log de restauration
   - Messages plus clairs à chaque étape

**Avant (comportement bugué) :**
```bash
# Si la base existait déjà avec des tables
# → Le script ajoutait les données par-dessus (peut causer des conflits)
# → Les tables pouvaient ne pas être restaurées correctement
```

**Après (comportement corrigé) :**
```bash
# La base est supprimée puis recréée
# → DROP DATABASE IF EXISTS
# → CREATE DATABASE
# → Import du dump SQL
# → Restauration complète et propre
```

**Test de validation :**
```bash
# Scénario de test :
1. Créer une table test dans une base
2. Lancer la sauvegarde
3. Supprimer la table test
4. Lancer la restauration
5. Vérifier que la table est bien restaurée

# Résultat attendu :
# ✓ La table test doit être présente après restauration
```

---

## Version 1.0 - 2025-11-27

### ✨ Création initiale

**Scripts créés :**
- `backup_intranet.sh` - Sauvegarde automatique MySQL + Web
- `restore.sh` - Restauration complète ou partielle

**Documentation :**
- `README.md` - Guide complet
- `QUICKSTART.md` - Démarrage rapide
- `CRONTAB_EXAMPLES.txt` - Exemples de configuration cron

**Fonctionnalités :**
- Sauvegarde MySQL (bases utilisateur uniquement)
- Sauvegarde site web
- Organisation par dossier horodaté
- Rotation automatique
- Logs détaillés
