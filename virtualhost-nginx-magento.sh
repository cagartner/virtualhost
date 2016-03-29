#!/bin/bash
### Set Language
TEXTDOMAIN=virtualhost

### Set default parameters
action=$1
domain=$2
rootDir=$3
owner=$(who am i | awk '{print $1}')
sitesEnable='/etc/nginx/sites-enabled/'
sitesAvailable='/etc/nginx/sites-available/'
userDir='/var/www/'

if [ "$(whoami)" != 'root' ]; then
	echo $"You have no permission to run $0 as non-root user. Use sudo"
		exit 1;
fi

if [ "$action" != 'create' ] && [ "$action" != 'delete' ]
	then
		echo $"You need to prompt for action (create or delete) -- Lower-case only"
		exit 1;
fi

while [ "$domain" == "" ]
do
	echo -e $"Please provide domain. e.g.dev,staging"
	read domain
done

if [ "$rootDir" == "" ]; then
	rootDir=${domain//./}
fi

### if root dir starts with '/', don't use /var/www as default starting point
if [[ "$rootDir" =~ ^/ ]]; then
	userDir=''
fi

rootDir=$userDir$rootDir

if [ "$action" == 'create' ]
	then
		### check if domain already exists
		if [ -e $sitesAvailable$domain ]; then
			echo -e $"This domain already exists.\nPlease Try Another one"
			exit;
		fi

		### check if directory exists or not
		if ! [ -d $userDir$rootDir ]; then
			### create the directory
			mkdir $userDir$rootDir
			### give permission to root dir
			chmod 755 $userDir$rootDir
			### write test file in the new domain dir
			if ! echo "<?php echo phpinfo(); ?>" > $userDir$rootDir/phpinfo.php
				then
					echo $"ERROR: Not able to write in file $userDir/$rootDir/phpinfo.php. Please check permissions."
					exit;
			else
					echo $"Added content to $userDir$rootDir/phpinfo.php."
			fi
		fi

		### create virtual host rules file
		if ! echo "server {
			listen   80;
			root $userDir$rootDir;
			index index.php index.html index.htm;
			server_name $domain;
			access_log /var/log/nginx/$domain.access.log;
    		error_log /var/log/nginx/$domain.error.log;

    		location / {
		        index index.html index.php; ## Allow a static html file to be shown first
		        try_files $uri $uri/ @handler; ## If missing pass the URI to Magento's front handler
		        expires 30d; ## Assume all files are cachable
		    }

    		## These locations would be hidden by .htaccess normally
		    location ^~ /app/                { deny all; }
		    location ^~ /includes/           { deny all; }
		    location ^~ /lib/                { deny all; }
		    location ^~ /media/downloadable/ { deny all; }
		    location ^~ /pkginfo/            { deny all; }
		    location ^~ /report/config.xml   { deny all; }
		    location ^~ /var/                { deny all; }

			# serve static files directly
			location ~* \.(jpg|jpeg|gif|css|png|js|ico|html)$ {
				access_log off;
				expires max;
			}

			 location /media {
		        try_files $uri /2.jpg;
		    }

		    location /var/export/ { ## Allow admins only to view export folder
		        auth_basic           "Restricted"; ## Message shown in login window
		        auth_basic_user_file htpasswd; ## See /etc/nginx/htpassword
		        autoindex            on;
		    }

		    location  /. { ## Disable .htaccess and other hidden files
		        return 404;
		    }

		    location @handler { ## Magento uses a common front handler
		        rewrite / /index.php;
		    }

		    location ~ .php/ { ## Forward paths like /js/index.php/x.js to relevant handler
		        rewrite ^(.*.php)/ $1 last;
		    }

			location ~ \.php$ {
				fastcgi_split_path_info ^(.+\.php)(/.+)\$;
				fastcgi_pass 127.0.0.1:9000;
				fastcgi_index index.php;
				include fastcgi_params;
			}

			location ~ /\.ht {
				deny all;
			}

		}" > $sitesAvailable$domain
		then
			echo -e $"There is an ERROR create $domain file"
			exit;
		else
			echo -e $"\nNew Virtual Host Created\n"
		fi

		### Add domain in /etc/hosts
		if ! echo "127.0.0.1	$domain" >> /etc/hosts
			then
				echo $"ERROR: Not able write in /etc/hosts"
				exit;
		else
				echo -e $"Host added to /etc/hosts file \n"
		fi

		if [ "$owner" == "" ]; then
			chown -R $(whoami):www-data $userDir$rootDir
		else
			chown -R $owner:www-data $userDir$rootDir
		fi

		### enable website
		ln -s $sitesAvailable$domain $sitesEnable$domain

		### restart Nginx
		service nginx restart

		### show the finished message
		echo -e $"Complete! \nYou now have a new Virtual Host \nYour new host is: http://$domain \nAnd its located at $userDir$rootDir"
		exit;
	else
		### check whether domain already exists
		if ! [ -e $sitesAvailable$domain ]; then
			echo -e $"This domain dont exists.\nPlease Try Another one"
			exit;
		else
			### Delete domain in /etc/hosts
			newhost=${domain//./\\.}
			sed -i "/$newhost/d" /etc/hosts

			### disable website
			rm $sitesEnable$domain

			### restart Nginx
			service nginx restart

			### Delete virtual host rules files
			rm $sitesAvailable$domain
		fi

		### check if directory exists or not
		if [ -d $userDir$rootDir ]; then
			echo -e $"Delete host root directory ? (s/n)"
			read deldir

			if [ "$deldir" == 's' -o "$deldir" == 'S' ]; then
				### Delete the directory
				rm -rf $userDir$rootDir
				echo -e $"Directory deleted"
			else
				echo -e $"Host directory conserved"
			fi
		else
			echo -e $"Host directory not found. Ignored"
		fi

		### show the finished message
		echo -e $"Complete!\nYou just removed Virtual Host $domain"
		exit 0;
fi
