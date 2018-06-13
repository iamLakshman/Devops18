#!/bin/bash

LOG=/tmp/stack.log
ID=$(id -u)

CONN_URL=http://www-us.apache.org/dist/tomcat/tomcat-connectors/jk/tomcat-connectors-1.2.43-src.tar.gz
CONN_TAR=$(echo $CONN_URL | awk -F / '{print $NF}')
CONN_DIR=$(echo $CONN_TAR | sed -e 's/.tar.gz//g')

TOMCAT_URL=$( curl -s https://tomcat.apache.org/download-90.cgi | grep Core: -A 20 | grep nofollow | grep tar.gz | cut -d '"' -f2)
TOMCAT_TAR=$(echo $TOMCAT_URL | awk -F / '{print $NF}')
TOMCAT_DIR=$(echo $TOMCAT_TAR | sed -e 's/.tar.gz//g')

STU_WAR=https://github.com/iamLakshman/Devops18/raw/master/APPSTACK/student.war
MYSQL_URL=https://github.com/iamLakshman/Devops18/raw/master/mysql-connector-java-5.1.40.jar
MYSQL_JAR=$(echo $MYSQL_URL | awk -F / '{print $NF}')

G="\e[32m"
R="\e[31m"
N="\e[0m"
Y="\e[33m"

VALIDATE(){
	if [ $1 -eq 0 ]; then
		echo -e "$2 ... $G SUCCEESS $N"
	else
		echo -e "$2 ... $R FAILED $N"
		exit 1
	fi

}

SKIP(){
	echo -e "$1 ...$Y SKIPPING $N"
}


if [ $ID -ne 0 ]; then
	echo "you should be the root user"
	exit 1
fi

yum install httpd -y &>>$LOG

VALIDATE $? "installing web server"

systemctl restart httpd &>>$LOG

VALIDATE $? "Restarting web server"

yum install java -y &>>$LOG

VALIDATE $? "installing Java"

cd /tomcat/

if [ -f $TOMCAT_TAR ]; then
	SKIP "Downloading TOMCAT"
else
	wget $TOMCAT_URL &>>$LOG
	VALIDATE $? "Downloading TOMCAT"
fi

if [ -d $TOMCAT_DIR ]; then
	SKIP "Extracting Tomcat"
else
	tar -xf $TOMCAT_TAR
	VALIDATE $? "Extracting TOMCAT"
fi

cd /tomcat/$TOMCAT_DIR/webapps

rm -rf *;

wget $STU_WAR &>>$LOG

VALIDATE $? "Downloading STUDENT project"

cd ../lib

if [ -f $MYSQL_JAR ];then
	SKIP "Downloading MYSQL Driver"
else
	wget $MYSQL_URL &>>$LOG
	VALIDATE $? "Downloading MySQL Jar"
fi

cd ../conf

sed -i -e '/TestDB/ d' context.xml

sed -i -e '$ i <Resource name="jdbc/TestDB" auth="Container" type="javax.sql.DataSource" maxTotal="100" maxIdle="30" maxWaitMillis="10000" username="student" password="student@1" driverClassName="com.mysql.jdbc.Driver" url="jdbc:mysql://localhost:3306/studentapp"/>' context.xml
			   
VALIDATE $? "Updating the context.xml"

cd ../bin

sh shutdown.sh &>>$LOG
sh startup.sh &>>$LOG

VALIDATE $? "Restarting Tomcat"

yum install mariadb mariadb-server -y &>>$LOG

VALIDATE $? "Installing MariaDB"

systemctl enable mariadb &>>$LOG

systemctl start mariadb

VALIDATE $? "Start mariadb"

echo "create database if not exists studentapp;
use studentapp;
CREATE TABLE if not exists Students(student_id INT NOT NULL AUTO_INCREMENT,
	student_name VARCHAR(100) NOT NULL,
    student_addr VARCHAR(100) NOT NULL,
	student_age VARCHAR(3) NOT NULL,
	student_qual VARCHAR(20) NOT NULL,
	student_percent VARCHAR(10) NOT NULL,
	student_year_passed VARCHAR(10) NOT NULL,
	PRIMARY KEY (student_id)
);
grant all privileges on studentapp.* to 'student'@'localhost' identified by 'student@1';" > /tmp/student.sql

VALIDATE $? "Creating student.sql"

mysql < /tmp/student.sql

VALIDATE $? "Created student schema and tables"

cd /opt/

if [ -f /opt/$CONN_TAR ]; then
	SKIP "Downloading Mod_jk"
else
	wget $CONN_URL -O /opt/$CONN_TAR &>>$LOG
	VALIDATE $? "Downloaing the MOD_JK"
fi

cd /opt/

if [ -d /opt/$CONN_DIR ]; then
	SKIP "Extracting the MOD_JK"
else
	tar -xf $CONN_TAR &>>$LOG
	VALIDATE $? "Extracting the MOD_JK"
fi

cd /opt/$CONN_DIR/native

yum install gcc httpd-devel -y &>>$LOG
VALIDATE $? "Downloaing GCC and httpd-devel"

cd /opt/$CONN_DIR/native

if [ -f /etc/httpd/modules/mod_jk.so ]; then
	SKIP "Compiling MOD_JK"
else
     ./configure --with-apxs=/bin/apxs &>>$LOG && make clean &>>$LOG && make &>>$LOG && make install &>>$LOG
	 VALIDATE $? "Compiling MOD_JK"
fi

cd /etc/httpd/conf.d

if [ -f /etc/httpd/conf.d/modjk.conf ]; then
	SKIP "creating mod_jk.conf"
else
    echo 'LoadModule jk_module modules/mod_jk.so
	JkWorkersFile conf.d/workers.properties
	JkLogFile logs/mod_jk.log
	JkLogLevel info
	JkLogStampFormat "[%a %b %d %H:%M:%S %Y]"
	JkOptions +ForwardKeySize +ForwardURICompat -ForwardDirectories
	JkRequestLogFormat "%w %V %T"
	JkMount /student tomcatA
	JkMount /student/* tomcatA' > modjk.conf
	VALIDATE $? "creating mod_jk.conf"
fi

if [ -f /etc/httpd/conf.d/workers.properties ]; then
	SKIP "Creating workers.properties"
else
	echo '### Define workers
	worker.list=tomcatA
	### Set properties
	worker.tomcatA.type=ajp13
	worker.tomcatA.host=localhost
	worker.tomcatA.port=8009' > workers.properties
	VALIDATE $? "Creating workers.properties"
fi

systemctl restart httpd &>>$LOG

VALIDATE $? "Restarting the webserver"

