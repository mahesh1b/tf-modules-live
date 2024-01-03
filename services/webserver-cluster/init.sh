#! /bin/bash
sudo apt-get update
sudo apt-get install -y apache2
sudo systemctl start apache2
sudo systemctl enable apache2
echo "<h1>${server_text}</h1>:<p>DB address: ${db_address}</p> <p>DB port: ${db_port}</p>" | sudo tee /var/www/html/index.html
