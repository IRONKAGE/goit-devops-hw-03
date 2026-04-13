# goit-devops-hw-03

***Технiчний опис завдань***

# **Завдання 3: Linux адміністрування**

## **Опис завдання:**

Створіть Bash-скрипт для автоматичного встановлення **Docker**, **Docker Compose**, **Python** і **Django**, а також ***запуште його в GitHub*** у гілку lesson-3.

## **Кроки виконання завдання:**

1. Створіть Bash-скрипт із назвою `install_dev_tools.sh`, який автоматично:
   - Встановлює Docker
   - Встановлює Docker Compose
   - Встановлює Python (версію 3.9 або новішу)
   - Встановлює Django через pip

   ```text
    ☝🏻 Скрипт має перевіряти, чи інструменти вже встановлені, щоб уникнути дублювання.
    ```

2. Зробіть скрипт виконуваним командою:

   ```bash
   chmod u+x install_dev_tools.sh
   ```

3. Запустіть скрипт на своїй системі, щоб переконатися, що всі інструменти встановлені правильно:

   ```bash
   ./install_dev_tools.sh
   ```

4. Запуште скрипт у створену гілку lesson-3 вашого репозиторію на GitHub:

   ```bash
   git checkout -b lesson-3
   git add install_dev_tools.sh
   git commit -m "Add Bash script for installing Docker, Docker Compose, Python, and Django"
   git push origin lesson-3
   ```
