#!/bin/bash

LOG=/tmp/stack.log
ID=$(id -u)

CONN_HTTP_URL=http://www-us.apache.org/dist/tomcat/tomcat-connectors/jk/tomcat-connectors-1.2.43-src.tar.gz
CONN_TAR_FILE=$(echo $CONN_HTTP_URL | cut -d / -f8) #echo $CONN_HTTP_URL | awk -F / '{print $NF}'
CONN_DIR_HOME=$(echo $CONN_TAR_FILE | sed -e 's/.tar.gz//g')

TOMCAT_HTTP_URL=$(curl -s https://tomcat.apache.org/download-90.cgi | grep Core: -A 20 | grep nofollow | grep tar.gz | cut -d '"' -f2)
TOMCAT_TAR_FILE=$(echo $TOMCAT_HTTP_URL | awk -F / '{print $NF}')
TOMCAT_DIR_HOME=$(echo $TOMACT_TAR_FILE | sed -e 's/.tar.gz//g')

STUDENT_WAR=https://github.com/iamLakshman/Devops18/raw/master/APPSTACK/student.war
MYSQL_JAR_URL=https://github.com/iamLakshman/Devops18/raw/master/mysql-connector-java-5.1.40.jar
MYSQL_JAR=$(echo MYSQL_JAR_URL | awk -F / '{print $NF}')

R="\e[31m"
G="\e[32m"
N="\e[0m"
Y="\e[33m"

VALIDATE(){
    if [ $1 -eq 0 ]; then
	    echo -e "$2 ..... $G Success $N"
	else
	    echo -e "$2 .... $R Failed $N"
	    exit 1
	fi

}


SKIP(){
    echo -e "$1 ....$Y SKIPPING $N"
	
}

if [ $ID -ne 0 ]; then
    echo "You should be the root user to perform this"
	exit 1
fi


yum install httpd -y &>>$LOG

VALIDATE $? "Installing Webserver"


systemctl restart httpd &>>$LOG

VALIDATE $? "Restarting the webserver"

yum install gcc httpd-devel,java -y &>>$LOG
VALIDATE $? "Installing gcc,httpd-devel,java"

if [ -f /opt/$CONN_TAR_FILE ]; then
    SKIP "Downloading Mod_Jk"
else
    wget $CONN_HTTP_URL -O /opt/$CONN_TAR_FILE &>>$LOG
    VALIDATE $? "Downloading Mod_Jk"
fi


cd /opt

if [ -d /opt/$CONN_DIR_HOME ]; then
    SKIP "Extracting Mod_Jk"
else
    tar -xf $CONN_TAR_FILE
    VALIDATE $? "Extracting Mod_Jk"
fi

if [ -f /etc/httpd/modules/mod_jk.so ]; then
    SKIP "Compiling Mod_Jk"
else
    cd $CONN_DIR_HOME/native
    ./configure --with-apxs=/bin/apxs &>>$LOG && make clean &>>$LOG && make &>>$LOG && make install &>>$LOG
     VALIDATE $? "Compiling Mod_Jk"
fi


cd /etc/httpd/conf.d

echo 'LoadModule jk_module modules/mod_jk.so
JkWorkersFile conf.d/workers.properties
JkLogFile logs/mod_jk.log
JkLogLevel info
JkLogStampFormat "[%a %b %d %H:%M:%S %Y]"
JkOptions +ForwardKeySize +ForwardURICompat -ForwardDirectories
JkRequestLogFormat "%w %V %T"
JkMount /student tomcatA
JkMount /student/* tomcatA' > modjk.conf

VALIDATE $? "Creating modjk.conf"

echo '### Define workers
worker.list=tomcatA
### Set properties
worker.tomcatA.type=ajp13
worker.tomcatA.host=localhost
worker.tomcatA.port=8009' > workers.properties

VALIDATE $? "Creating workers.properties"

cd /opt

if [ -f apache-tomcat-9.0.6.tar.gz ]; then
    SKIP "Downloading tomcat"
else
    wget $TOMCAT_HTTP_URL &>>$LOG
	VALIDATE $? "Downloading Tomcat"
fi

if [ -d $TOMCAT_DIR_HOME ]; then
    SKIP "Extracting Tomcat"
else
    tar -xf $TOMCAT_TAR_FILE
	VALIDATE $? "Extracting Tomcat"
fi 

cd /opt/apache-tomcat-9.0.6/webapps

rm -rf *;

wget $STUDENT_WAR &>>$LOG

VALIDATE $? "Downloading Student Project....Success"

cd ../lib

if [ -f $MYSQL_JAR ]; then
    SKIP "Download MySql Driver"
else
    wget $MYSQL_JAR_URL &>>$LOG
	VALIDATE $? "Download MySql Driver"
fi

cd /opt/apache-tomcat-9.0.6/conf

sed -i -e '/TestDB/ d' context.xml

sed -i -e '$ i <Resource name="jdbc/TestDB" auth="Container" type="javax.sql.DataSource" maxTotal="100" maxIdle="30" maxWaitMillis="10000" username="student" password="student@1" driverClassName="com.mysql.jdbc.Driver" url="jdbc:mysql://localhost:3306/studentapp"/>' context.xml

VALIDATE $? "Configuring Context.xml"

yum install mariadb mariadb-server -y &>>$LOG
VALIDATE $? "Installind Mariadb"

systemctl restart mariadb &>>$LOG
VALIDATE $? "Running Mariadb"

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

mysql < /tmp/student.sql

VALIDATE $? "Creating Database"

cd ../bin

sh shutdown.sh &>>$LOG

sh startup.sh &>>$LOG

VALIDATE $? "Restarting Tomcat"




