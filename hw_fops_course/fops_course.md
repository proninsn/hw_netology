# Курсовая работа на профессии "DevOps-инженер с нуля" - Пронин Сергей Николаевич

- Конфигурация terraform
    - [main](main.tf)  
    - [variables](variables.tf)

- Конфигурация Ansible
     - [inventory.yml](inventory.yml)
     - [webservers.yml](webservers.yml)
     - [zabbix.yml](zabbix.yml)
     - [logging.yml](logging.yml)
     - [filebeat.yml](filebeat.yml)

Зравствуйте!

**Вопрос:**  
У меня получилось создать инфраструктуру через terraform. Но не могу запустить ansible-playbook inventory.yml webservers.yml уже по-разному перепробовал, но не получается. При этом я могу подключиться по ssh к ВМ командой: ssh -o ProxyCommand="ssh -W %h:%p -i ~/.ssh/id_25519 ubuntu@158.160.54.150" ubuntu@192.168.10.20 Прошу помочь.

 **Скрин ошибки**  
 ![img_course-03.JPG](images/img_course-03.JPG)