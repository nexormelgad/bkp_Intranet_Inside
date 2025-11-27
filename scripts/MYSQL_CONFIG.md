# 🔐 Configuration MySQL pour Sauvegarde et Restauration

## Vue d'ensemble

Pour des raisons de **sécurité**, nous utilisons **deux utilisateurs MySQL distincts** :

| Utilisateur | Fichier Config | Droits | Utilisation |
|-------------|----------------|--------|-------------|
| `backupuser` | `/root/.my.cnf` | Lecture seule | Script de **sauvegarde** |
| `restoreuser` | `/root/.my_restore.cnf` | Tous les droits | Script de **restauration** |

**Principe** : L'utilisateur de sauvegarde (qui tourne en cron) n'a que les droits minimums. L'utilisateur de restauration (utilisé rarement) a tous les droits.

---

## 📋 Étape 1 : Utilisateur de Sauvegarde (déjà configuré)

### Créer l'utilisateur

```sql
CREATE USER 'backupuser'@'localhost' IDENTIFIED BY 'MotDePasseSauvegarde';
GRANT SELECT, LOCK TABLES, SHOW VIEW, EVENT, TRIGGER ON *.* TO 'backupuser'@'localhost';
FLUSH PRIVILEGES;
```

### Fichier de configuration

```bash
cat > /root/.my.cnf << 'EOF'
[client]
user=backupuser
password=MotDePasseSauvegarde
EOF

chmod 600 /root/.my.cnf
```

✅ **Utilisé par** : `/mnt/backup/scripts/backup_intranet.sh`

---

## 🔧 Étape 2 : Utilisateur de Restauration (NOUVEAU)

### Créer l'utilisateur

```bash
mysql -u root -p
```

```sql
-- Créer l'utilisateur de restauration
CREATE USER 'restoreuser'@'localhost' IDENTIFIED BY 'MotDePasseRestauration';

-- Donner TOUS les droits (nécessaire pour CREATE/DROP DATABASE)
GRANT ALL PRIVILEGES ON *.* TO 'restoreuser'@'localhost';

-- Appliquer les changements
FLUSH PRIVILEGES;

-- Vérifier les droits
SHOW GRANTS FOR 'restoreuser'@'localhost';

-- Quitter
EXIT;
```

**Résultat attendu** :
```
GRANT ALL PRIVILEGES ON *.* TO 'restoreuser'@'localhost'
```

### Fichier de configuration

```bash
cat > /root/.my_restore.cnf << 'EOF'
[client]
user=restoreuser
password=MotDePasseRestauration
EOF

chmod 600 /root/.my_restore.cnf
chown root:root /root/.my_restore.cnf
```

### Tester l'utilisateur

```bash
# Tester la connexion
mysql --defaults-file=/root/.my_restore.cnf -e "SHOW DATABASES;"

# Tester la création de base
mysql --defaults-file=/root/.my_restore.cnf -e "
CREATE DATABASE test_restore_rights;
DROP DATABASE test_restore_rights;
"
```

✅ **Utilisé par** : `/mnt/backup/scripts/restore.sh`

---

## 📊 Résumé de la Configuration

### Structure des fichiers

```
/root/
├── .my.cnf              → backupuser (lecture seule)
└── .my_restore.cnf      → restoreuser (tous droits)
```

### Scripts et utilisateurs

```
backup_intranet.sh
    ↓
/root/.my.cnf (backupuser)
    ↓
SELECT, LOCK TABLES, SHOW VIEW
    ✅ Sauvegarde seulement

restore.sh
    ↓
/root/.my_restore.cnf (restoreuser)
    ↓
ALL PRIVILEGES
    ✅ DROP DATABASE
    ✅ CREATE DATABASE
    ✅ Restauration complète
```

---

## 🔒 Sécurité

### Permissions des fichiers

```bash
# Vérifier les permissions
ls -l /root/.my*.cnf

# Doivent afficher :
# -rw------- 1 root root ... .my.cnf
# -rw------- 1 root root ... .my_restore.cnf
```

### Bonnes pratiques

✅ **Mots de passe différents** pour backupuser et restoreuser
✅ **Permissions 600** sur les fichiers de config (lecture root uniquement)
✅ **Utilisateurs localhost** uniquement (pas d'accès distant)
✅ **Principe du moindre privilège** : backupuser ne peut pas modifier les données

---

## 🚨 Alternative : Un Seul Utilisateur (NON RECOMMANDÉ)

Si vous préférez utiliser un seul utilisateur pour les deux opérations :

```sql
-- Donner tous les droits à backupuser
GRANT ALL PRIVILEGES ON *.* TO 'backupuser'@'localhost';
FLUSH PRIVILEGES;
```

Puis modifier le script de restauration :

```bash
# Dans /mnt/backup/scripts/restore.sh, ligne 41 :
MYSQL_CNF="/root/.my.cnf"  # Au lieu de /root/.my_restore.cnf
```

⚠️ **Inconvénient** : Le script de sauvegarde qui tourne en cron aura tous les droits, ce qui est un risque de sécurité.

---

## ✅ Checklist de Configuration

- [ ] Utilisateur `backupuser` créé avec droits SELECT
- [ ] Fichier `/root/.my.cnf` créé et sécurisé (chmod 600)
- [ ] Script de sauvegarde testé avec succès
- [ ] Utilisateur `restoreuser` créé avec ALL PRIVILEGES
- [ ] Fichier `/root/.my_restore.cnf` créé et sécurisé (chmod 600)
- [ ] Connexion avec restoreuser testée
- [ ] Script de restauration testé avec succès

---

## 🧪 Test Complet

```bash
# 1. Test de la sauvegarde
/mnt/backup/scripts/backup_intranet.sh
# Doit réussir avec backupuser

# 2. Test de la restauration
cd $(ls -1dt /mnt/backup/202* | head -n1)
/mnt/backup/scripts/restore.sh --db-only
# Doit réussir avec restoreuser

# 3. Vérifier les logs
cat backup.log
cat restore_*.log
```

---

## 📞 Dépannage

### Erreur : "Access denied for user 'backupuser'"

**Cause** : backupuser n'a pas les droits nécessaires

**Solution** : Créer restoreuser avec ALL PRIVILEGES (voir Étape 2)

### Erreur : "ERROR 1045 (28000): Access denied"

**Cause** : Mot de passe incorrect dans le fichier .cnf

**Solution** :
```bash
# Vérifier le contenu
cat /root/.my_restore.cnf

# Tester manuellement
mysql -u restoreuser -p
```

### Erreur : "Can't connect to MySQL server"

**Cause** : MySQL n'est pas démarré

**Solution** :
```bash
systemctl status mysql
systemctl start mysql
```

---

**Version** : 1.2
**Date** : 2025-11-28
**Impact** : Configuration requise pour la restauration
