#!/bin/bash

ID=$(id -u)
LOG=/tmp/stack.log
R="\e[31m"
G="\e[32m"
Y="\e[33m"
N="\e[0m"
MOD_JK_URL=http://mirrors.fibergrid.in/apache/tomcat/tomcat-connectors/jk/tomcat-connectors-1.2.43-src.tar.gz
MOD_JK_TAR_FILE=$(echo $MOD_JK_URL | cut -d / -f8) #echo $MOD_JK_URL | awk -F / '{ print $NF }'
MOD_JK_HOME=$(echo $MOD_JK_TAR_FILE | sed -e 's/.tar.gz//' )

TOMCAT_URL=$(curl -s https://tomcat.apache.org/download-90.cgi | grep Core: -A 20 | grep nofollow | grep tar.gz | cut -d '"' -f2)
TOMCAT_TAR_FILE=$(echo $TOMCAT_URL | awk -F / '{ print $NF }')
TOMCAT_HOME=$(echo $TOMCAT_TAR_FILE | sed -e 's/.tar.gz//' )
MYSQL_JAR_URL=https://github.com/devops2k18/DevOpsAug/raw/master/APPSTACK/mysql-connector-java-5.1.40.jar
MYSQL_JAR_FILE=$(echo $MYSQL_JAR_URL | awk -F / '{ print $NF }')

VALIDATE(){
	if [ $1 -ne 0 ]; then
		echo -e "$2 ... $R FAILED $N"
		exit 2
	else
		echo -e "$2 ... $G SUCCESS $N"
	fi
}

SKIP(){
	echo -e "$1 ...$Y SKIPPING $N"
}

if [ $ID -ne 0 ]; then
	echo "You dont have persmissions to run this script"
	exit 2
else
	echo "You are the root user, you can run this script"
fi

yum install httpd java -y &>> $LOG

VALIDATE $? "Installing HTTP SERVER"

systemctl enable httpd &>> $LOG

VALIDATE $? "Enabling httpd"

systemctl start httpd &>> $LOG

VALIDATE $? "Starting HTTP server"

if [ -f /root/$MOD_JK_TAR_FILE ];then
	SKIP "Downloading MOD_JK"
else
	wget $MOD_JK_URL -O /root/$MOD_JK_TAR_FILE &>> $LOG
	VALIDATE $? "Downloading MOD_JK"
fi

cd /root

if [ -d $MOD_JK_HOME ]; then
	SKIP "Extracting MOD_JK"
else
	tar -xf $MOD_JK_TAR_FILE &>> $LOG
	VALIDATE $? "Extracting MOD_JK"
fi

cd $MOD_JK_HOME/native

yum install gcc httpd-devel -y &>> $LOG

VALIDATE $? "Installing gcc and httpd-devel"

if [ -f /etc/httpd/modules/mod_jk.so ]; then
	SKIP "Compiling MOD_JK"
else
	./configure --with-apxs=/bin/apxs &>> $LOG && make &>> $LOG && make install &>> $LOG
	VALIDATE $? "Compiling MOD_JK"
fi

cd /etc/httpd/conf.d

if [ -f modjk.conf ] ; then
	SKIP "Creating modjk.conf"
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
VALIDATE $? "Creating modjk.conf"
fi

if [ -f workers.properties ] ; then
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

systemctl restart httpd &>> $LOG

VALIDATE $? "restarting httpd"

cd /root

if [ -f $TOMCAT_TAR_FILE ]; then
	SKIP "Downloading TOMCAT"
else
	wget $TOMCAT_URL &>> $LOG
	VALIDATE $? "Downloading TOMCAT"
fi

if [ -d $TOMCAT_HOME ]; then
	SKIP "Extracting TOMCAT"
else
	tar -xf $TOMCAT_TAR_FILE &>> $LOG
	VALIDATE $? "Extracting TOMCAT"
fi

cd $TOMCAT_HOME/conf

sed -i '/TestDB/ d' context.xml

sed -i '$ i <Resource name="jdbc/TestDB" auth="Container" type="javax.sql.DataSource" maxTotal="100" maxIdle="30" maxWaitMillis="10000" username="student" password="student@1" driverClassName="com.mysql.jdbc.Driver" url="jdbc:mysql://localhost:3306/studentapp"/>' context.xml

cd ../lib

if [ -f $MYSQL_JAR_FILE ];then
	SKIP "Downloading MYSQL driver"
else
	wget $MYSQL_JAR_URL &>> $LOG
	VALIDATE $? "Downloading MYSQL driver"
fi

cd ../webapps

wget https://github.com/devops2k18/DevOpsAug/raw/master/APPSTACK/student.war &>> $LOG

cd ../bin

sh ./shutdown.sh &>> $LOG

sh ./startup.sh &>> $LOG

VALIDATE $? "Starting the TOMCAT server"


yum install mariadb mariadb-server -y &>> $LOG

VALIDATE $? "Installing MariaDB server"

systemctl enable mariadb &>> $LOG

VALIDATE $? "Enabling MariaDB"

systemctl start mariadb &>> $LOG

VALIDATE $? "Starting MariaDB"

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

VALIDATE $? "creating database"
