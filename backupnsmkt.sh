#!/bin/bash
#
# Mikrotik SSH backup script

LOCAL_DIR=$(dirname "$0")
HOST=$(hostname)
BACKUP_PATH=/FullPath/Mikrotik-backupBackBone-ssh/mikrotik
CONF=$LOCAL_DIR/backupnsmkt.conf
LOG=$LOCAL_DIR/logs/backupnsmkt$(date +%Y%m%d-%T).log
SSH_USER=USER1
SSH_PASS=CLAVE1
SSH_USER2=USER2
SSH_PASS2=CLAVE2
SSH_USER3=USER3
SSH_PASS3=CLAVE3
DELETE_FILE=yes
MAIL_FROM=sender-permited@dominio.com
MAIL_TO=report@dominio.com

echo -e "\033[1mScript Backup Mikrotik SDT Clientes via SSH\033[0m"
echo ""

if [ ! -f "$CONF" ] 2>/dev/null; then
    echo -e "\e[31m!!!ERROR\e[0m, Archivo de configuracion no encontrado!"
    exit 1
fi

if [ ! -d "$BACKUP_PATH" ]; then
    echo -e "\e[31m!!!ERROR\e[0m, Ruta de backup no encontrada!"
    exit 1
fi

LAST_CHAR=$(tail -c 1 "$CONF")
if [ "$LAST_CHAR" != "" ]; then
    echo -e "" >>$CONF
fi

INDEX=0
SCP_ERROR=no

while read -r line; do
    line=$(echo "$line" | grep :)
    if [ -n "$line" ]; then
        if [ "${line:0:1}" != "#" ]; then
            IP[$INDEX]=$(echo "$line" | cut -d: -f1 | tr -d " ")
            DESC[$INDEX]=$(echo "$line" | cut -d: -f2 | tr -d " ")
            if [ ! -d "${BACKUP_PATH}/${DESC[$INDEX]}" ]; then
                mkdir -p "${BACKUP_PATH}/${DESC[$INDEX]}"
            fi
            INDEX=$((INDEX + 1))
        fi
    fi
done <"$CONF"

cmd="/system package print file=backupmktsdt.txt; /export file=backupmktsdt.rsc; /system backup save name=backupmktsdt.backup;"
#cmd="/system package print file=backupmktsdt.txt; /export file=backupmktsdt.rsc;"
echo "$cmd" >$LOG
echo "--------------------------------------------------------------------------------" >>$LOG

# Function to attempt SSH connection with multiple credentials
attempt_ssh_connection() {
    local ip=$1
    local cmd=$2
    if timeout 15s sshpass -p "$SSH_PASS" ssh -o StrictHostKeyChecking=no -o HostKeyAlgorithms=+ssh-dss -o KexAlgorithms=diffie-hellman-group14-sha1 "$SSH_USER@$ip" "$cmd" >/dev/null 2>&1; then
        echo "$SSH_USER" "$SSH_PASS"
    else
        echo "!!! Conexion SSH fallo con la primera credencial!" >>$LOG
        if timeout 20s sshpass -p "$SSH_PASS2" ssh -o StrictHostKeyChecking=no -o HostKeyAlgorithms=+ssh-dss -o KexAlgorithms=diffie-hellman-group14-sha1 "$SSH_USER2@$ip" "$cmd" >/dev/null 2>&1; then
            echo "$SSH_USER2" "$SSH_PASS2"
        else
            echo "!!! Conexion SSH fallo con la segunda credencial!" >>$LOG
            if timeout 15s sshpass -p "$SSH_PASS3" ssh -o StrictHostKeyChecking=no -o HostKeyAlgorithms=+ssh-dss -o KexAlgorithms=diffie-hellman-group14-sha1 "$SSH_USER3@$ip" "$cmd" >/dev/null 2>&1; then
                echo "$SSH_USER3" "$SSH_PASS3"
            else
                echo "!!! Conexion SSH fallo con la tercera credencial!" >>$LOG
                echo ""
            fi
        fi
    fi
}

# Function to attempt SCP transfer with the given credentials
attempt_scp_transfer() {
    local user=$1
    local pass=$2
    local ip=$3
    local file=$4
    local dest=$5
    timeout 15s sshpass -p "$pass" scp -o StrictHostKeyChecking=no -o HostKeyAlgorithms=+ssh-dss -o KexAlgorithms=diffie-hellman-group14-sha1 "$user@$ip:/$file" "$dest" >/dev/null 2>&1
}

for ((a = 0; a < INDEX; a++)); do
    echo "${IP[$a]} -  ${DESC[$a]}"
    echo "${IP[$a]} -  ${DESC[$a]}" >>$LOG

    credentials=$(attempt_ssh_connection "${IP[$a]}" "$cmd")
    if [ -n "$credentials" ]; then
        read -r user pass <<<"$credentials"
        SCP_ERROR=no
        echo -e " \e[32mOK\e[0m Conexion SSH establecida con las credenciales correctas."
        echo "!!! Conexion SSH establecida con ${user} en ${IP[$a]}" >>$LOG
    else
        echo -e " \e[31mErr\e[0m Conexion SSH fallo!"
        echo "!!! Conexion SSH fallo!" >>$LOG
        SCP_ERROR=yes
        continue
    fi

    sleep 2

    for SCPFILE in backupmktsdt.backup backupmktsdt.rsc backupmktsdt.txt; do
        if attempt_scp_transfer "$user" "$pass" "${IP[$a]}" "$SCPFILE" "${BACKUP_PATH}/${DESC[$a]}/"; then
            echo -e " \e[32mOK\e[0m  Transferencia desde ${DESC[$a]} completa."
            echo "!!! Transferencia desde ${DESC[$a]} completa con ${user}" >>$LOG
            mv "${BACKUP_PATH}/${DESC[$a]}/${SCPFILE}" "${BACKUP_PATH}/${DESC[$a]}/$(date +%Y%m%d)_${SCPFILE}"
            if [ "$DELETE_FILE" == "yes" ]; then
                cmd2="/file remove ${SCPFILE};"
                timeout 5s sshpass -p "$pass" ssh -o StrictHostKeyChecking=no -o HostKeyAlgorithms=+ssh-dss -o KexAlgorithms=diffie-hellman-group14-sha1 "$user@${IP[$a]}" "$cmd2"
                if [ $? != 0 ]; then
                    echo -e " \e[31mErr\e[0m Borrado de archivo ${DESC[$a]} del SDT Mikrotik fallo!"
                    echo "!!! Borrado de archivo ${SCPFILE} desde SDT Mikrotik fallo!" >>$LOG
                else
                    echo -e " \e[32mOK\e[0m  Borrado de archivo ${DESC[$a]} del SDT Mikrotik."
                fi
            fi
        else
            echo -e " \e[31mErr\e[0m Transferencia desde ${DESC[$a]} fallo!"
            echo "!!! Transferencia desde ${DESC[$a]} fallo!" >>$LOG
            SCP_ERROR=yes
        fi
    done

    mv "${BACKUP_PATH}/${DESC[$a]}/$(date +%Y%m%d)_backupmktsdt.backup" "${BACKUP_PATH}/${DESC[$a]}/$(date +%Y%m%d)_${DESC[$a]}.backup"
    mv "${BACKUP_PATH}/${DESC[$a]}/$(date +%Y%m%d)_backupmktsdt.rsc" "${BACKUP_PATH}/${DESC[$a]}/$(date +%Y%m%d)_${DESC[$a]}.rsc"
    mv "${BACKUP_PATH}/${DESC[$a]}/$(date +%Y%m%d)_backupmktsdt.txt" "${BACKUP_PATH}/${DESC[$a]}/$(date +%Y%m%d)_${DESC[$a]}.txt"
    echo ""
    echo "--------------------------------------------------------------------------------" >>$LOG
done

if [ "$SCP_ERROR" == "yes" ]; then
    echo -e ""
    echo -e "\e[31m Err\e[0m \033[1m Cuando un backup se copiaba ocurrio un\033[0m \e[31mERROR\e[0m \033"
    echo -e "$(date "+%Y-%m-%d %T") \t  !!!ERROR - Cuando un backup se copiaba ocurrio un error." >>$LOG
    echo ""
    echo -e "\033[1mRevisar el archivo de log: $LOG \033[0m"
    echo -e "!!!ERROR - Cuando un backup se copiaba ocurrio un ERROR.\nRevisar el archivo de log del servidor para $HOST: $LOG" | mail -s "Servidor: $HOST - Backup de Mikrotiks finalizo con ERRORES!" -r $MAIL_FROM $MAIL_TO
else
    echo -e ""
    echo -e " \e[32mOK\e[0m  \033[1mScript de backup completado.\033[0m"
    echo -e "$(date "+%Y-%m-%d %T") \t  OK - Script de backup completado." >>$LOG
fi
sleep 5
echo ""
