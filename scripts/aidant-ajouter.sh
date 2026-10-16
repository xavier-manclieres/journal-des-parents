#!/usr/bin/env bash
# Gère les comptes de la page /aidants.
# Usage : /opt/n8n/aidant-ajouter.sh                      (ajout, ou changement de mot de passe)
#         /opt/n8n/aidant-ajouter.sh --editeur Prénom     (peut modifier/supprimer TOUS les événements)
#         /opt/n8n/aidant-ajouter.sh --standard Prénom    (retire ce droit : seulement ses propres événements)
#         /opt/n8n/aidant-ajouter.sh --retirer Prénom     (supprime le compte)
#         /opt/n8n/aidant-ajouter.sh --liste              (comptes et droits)
#         /opt/n8n/aidant-ajouter.sh --synchro            (renvoie tous les comptes et rôles vers Airtable)
# Le rôle de chaque compte est aussi enregistré dans la table Airtable « Aidants ».
# Droits : tout aidant (rôle « Standard ») dicte, consulte l'agenda, joint des documents, et peut
# modifier ou supprimer les événements issus de SES notes.
# « Éditeur » = peut en plus modifier ou supprimer TOUS les événements.
set -euo pipefail
# Préfixe secret des webhooks n8n (chemin /webhook/<WEBHOOK_TOKEN>-compte), à définir dans l'environnement.
WEBHOOK_TOKEN="${WEBHOOK_TOKEN:?définir WEBHOOK_TOKEN, par exemple aidants-xxxxxxxxxxxx}"
D=/opt/n8n/caddy-conf
F=$D/aidants.users          # tous les comptes
E=$D/aidants.editeurs       # comptes éditeurs (contrôlé par Caddy sur les routes rdv-*)
J=/opt/n8n/aidants-site/editeurs.json   # liste affichée par la page (menu d'appui long)
mkdir -p "$D" "$(dirname "$J")"; touch "$F" "$E"; chmod 600 "$F" "$E"

recharger() {
  docker exec n8n-caddy-1 caddy reload --config /etc/caddy/Caddyfile
}

# Caddy refuse un bloc basic_auth vide : on garde un compte factice inutilisable.
maj_editeurs() {
  if [ ! -s "$E" ]; then
    P=$(head -c 24 /dev/urandom | base64)
    H=$(docker run --rm caddy:latest caddy hash-password --plaintext "$P"); unset P
    echo "_inactif $H" > "$E"; chmod 600 "$E"
  fi
  NOMS=$(grep -v '^_inactif ' "$E" | cut -d' ' -f1 | sed 's/.*/"&"/' | paste -sd, - || true)
  printf '[%s]\n' "$NOMS" > "$J"; chmod 644 "$J"
}

# Miroir dans Airtable (table Aidants) via n8n, joint depuis le réseau Docker (non exposé à Internet).
airtable() {  # airtable Prénom maj|retirer [Éditeur|Standard]
  local corps
  corps=$(printf '{"prenom":"%s","action":"%s","role":"%s"}' "$1" "$2" "${3:-Standard}")
  docker exec n8n-caddy-1 wget -q -O /dev/null --timeout=20 --header='Content-Type: application/json' \
    --post-data="$corps" "http://n8n:5678/webhook/${WEBHOOK_TOKEN}-compte" \
    || echo "Attention : Airtable n'a pas pu être mis à jour pour $1 (le droit réel, lui, est bien appliqué)."
}
role_de() { if grep -q "^$1 " "$E"; then echo "Éditeur"; else echo "Standard"; fi; }

retirer_editeur() { grep -v "^$1 " "$E" > "$E.tmp" || true; mv "$E.tmp" "$E"; chmod 600 "$E"; }

existe() { grep -q "^$1 " "$F"; }

if [ "${1:-}" = "--retirer" ]; then
  NOM="${2:?Prénom à retirer manquant}"
  grep -v "^${NOM} " "$F" > "$F.tmp" || true; mv "$F.tmp" "$F"; chmod 600 "$F"
  retirer_editeur "$NOM"; maj_editeurs; recharger
  airtable "$NOM" retirer
  echo "Retiré : $NOM"; exit 0
fi

if [ "${1:-}" = "--editeur" ]; then
  NOM="${2:?Prénom manquant}"
  existe "$NOM" || { echo "Compte inconnu : $NOM"; exit 1; }
  retirer_editeur "$NOM"; grep "^$NOM " "$F" >> "$E"
  maj_editeurs; recharger
  airtable "$NOM" maj "Éditeur"
  echo "OK : $NOM peut modifier et supprimer tous les événements."; exit 0
fi

if [ "${1:-}" = "--standard" ] || [ "${1:-}" = "--lecture" ]; then
  NOM="${2:?Prénom manquant}"
  existe "$NOM" || { echo "Compte inconnu : $NOM"; exit 1; }
  retirer_editeur "$NOM"; maj_editeurs; recharger
  airtable "$NOM" maj "Standard"
  echo "OK : $NOM est standard (gère seulement ses propres événements)."; exit 0
fi

if [ "${1:-}" = "--synchro" ]; then
  while read -r N _; do airtable "$N" maj "$(role_de "$N")"; echo "Synchronisé : $N ($(role_de "$N"))"; done < "$F"
  exit 0
fi

if [ "${1:-}" = "--liste" ]; then
  while read -r N _; do
    if grep -q "^$N " "$E"; then echo "$N : éditeur (tous les événements)"; else echo "$N : standard (ses événements)"; fi
  done < "$F"
  exit 0
fi

read -r -p "Prénom (identifiant, sans accent ni espace, ex. Helene) : " NOM
[[ "$NOM" =~ ^[A-Za-z][A-Za-z-]*$ ]] || { echo "Prénom refusé : lettres sans accent et tirets uniquement."; exit 1; }
read -r -s -p "Mot de passe de $NOM : " M1; echo
read -r -s -p "Confirmation : " M2; echo
[ -n "$M1" ] && [ "$M1" = "$M2" ] || { echo "Mots de passe vides ou différents, rien n'est modifié."; exit 1; }
if existe "$NOM" && grep -q "^$NOM " "$E"; then DEF="O"; else DEF="N"; fi
read -r -p "Droit de modifier ou supprimer TOUS les événements (sinon : seulement les siens) ? (o/N, Entrée = non) : " REP
case "${REP:-}" in [oO]*) EDIT=1;; [nN]*) EDIT=0;; *) [ "$DEF" = "O" ] && EDIT=1 || EDIT=0;; esac
H=$(docker run --rm caddy:latest caddy hash-password --plaintext "$M1"); unset M1 M2
grep -v "^${NOM} " "$F" > "$F.tmp" || true
echo "$NOM $H" >> "$F.tmp"
mv "$F.tmp" "$F"; chmod 600 "$F"
retirer_editeur "$NOM"
[ "$EDIT" = 1 ] && echo "$NOM $H" >> "$E"
maj_editeurs; recharger
airtable "$NOM" maj "$(role_de "$NOM")"
[ "$EDIT" = 1 ] && DROIT="éditeur (tous les événements)" || DROIT="standard (ses événements)"
echo "OK : $NOM peut se connecter, droits : $DROIT. Aidants enregistrés : $(cut -d' ' -f1 "$F" | paste -sd, -)"
