# 🚀 Guide de Démarrage Rapide - Sauvegarde VPS

## ⚡ Installation Rapide (5 minutes)

### 1. Les scripts sont déjà créés et exécutables ✓

```bash
ls -lh /mnt/backup/scripts/
```

### 2. Créer les utilisateurs MySQL

```bash
mysql -u root -p
```

```sql
-- Utilisateur de sauvegarde (lecture seule)
CREATE USER 'backupuser'@'localhost' IDENTIFIED BY 'MotDePasseSauvegarde';
GRANT SELECT, LOCK TABLES, SHOW VIEW, EVENT, TRIGGER ON *.* TO 'backupuser'@'localhost';

-- Utilisateur de restauration (tous droits)
CREATE USER 'restoreuser'@'localhost' IDENTIFIED BY 'MotDePasseRestauration';
GRANT ALL PRIVILEGES ON *.* TO 'restoreuser'@'localhost';

FLUSH PRIVILEGES;
EXIT;
```

### 3. Créer les fichiers de configuration MySQL

```bash
# Fichier pour la sauvegarde
cat > /root/.my.cnf << 'EOF'
[client]
user=backupuser
password=MotDePasseSauvegarde
EOF

chmod 600 /root/.my.cnf

# Fichier pour la restauration
cat > /root/.my_restore.cnf << 'EOF'
[client]
user=restoreuser
password=MotDePasseRestauration
EOF

chmod 600 /root/.my_restore.cnf
```

### 4. Tester la sauvegarde

```bash
/mnt/backup/scripts/backup_intranet.sh
```

### 5. Vérifier le résultat

```bash
ls -lh /mnt/backup/$(date +'%Y%m%d')_*
cat /mnt/backup/$(date +'%Y%m%d')_*/backup.log
```

---

## 📅 Automatiser avec Cron

### Sauvegardes 3 fois par jour (recommandé)

```bash
crontab -e
```

Ajouter :
```cron
0 2 * * * /mnt/backup/scripts/backup_intranet.sh >/dev/null 2>&1
0 12 * * * /mnt/backup/scripts/backup_intranet.sh >/dev/null 2>&1
0 18 * * * /mnt/backup/scripts/backup_intranet.sh >/dev/null 2>&1
```

---

## 🔄 Restaurer une Sauvegarde

### Restauration complète

```bash
# 1. Aller dans le dossier de sauvegarde
cd /mnt/backup/20251127_1425

# 2. Lancer la restauration
/mnt/backup/scripts/restore.sh
```

### Options de restauration

```bash
# Seulement le site web
/mnt/backup/scripts/restore.sh --web-only

# Seulement les bases de données
/mnt/backup/scripts/restore.sh --db-only
```

---

## 📋 Commandes Utiles

### Lister les sauvegardes

```bash
ls -lhd /mnt/backup/2025*
```

### Voir le dernier log

```bash
cat $(ls -1dt /mnt/backup/2025* | head -n1)/backup.log
```

### Vérifier l'espace disque

```bash
du -sh /mnt/backup
df -h /mnt/backup
```

### Nettoyer manuellement (> 30 jours)

```bash
find /mnt/backup -mindepth 1 -maxdepth 1 -type d -mtime +30 -exec rm -rf {} \;
```

---

## 🆘 Dépannage Rapide

### Erreur de connexion MySQL (sauvegarde) ?

```bash
# Vérifier le fichier de config
cat /root/.my.cnf

# Tester la connexion
mysql --defaults-file=/root/.my.cnf -e "SHOW DATABASES;"
```

### Erreur "Access denied" lors de la restauration ?

```bash
# Vérifier le fichier de config de restauration
cat /root/.my_restore.cnf

# Tester la connexion avec restoreuser
mysql --defaults-file=/root/.my_restore.cnf -e "SHOW DATABASES;"

# Vérifier les droits
mysql -u root -p -e "SHOW GRANTS FOR 'restoreuser'@'localhost';"
```

### Permissions incorrectes ?

```bash
chmod 600 /root/.my.cnf
chmod 600 /root/.my_restore.cnf
chmod +x /mnt/backup/scripts/*.sh
```

### Voir les erreurs

```bash
grep -i "erreur" /mnt/backup/2025*/backup.log
grep -i "erreur" /mnt/backup/2025*/restore_*.log
```

---

## 📚 Documentation Complète

Pour plus de détails, consultez : `/mnt/backup/scripts/README.md`

```bash
cat /mnt/backup/scripts/README.md
```

---

**Bon à savoir** :
- ✅ Rétention par défaut : 8 jours
- ✅ Bases système exclues automatiquement
- ✅ Un dossier unique par sauvegarde
- ✅ Logs détaillés dans chaque dossier
- ✅ Possibilité de multiples sauvegardes par jour
