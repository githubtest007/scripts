#!/bin/bash

deployFlag=""
serviceJenkinsBuildUrl=""
#判断文件中是否包含指定字符串
isContainsString(){
        grep "$1" $2 > /dev/null
        if [ $? -eq 0 ]; then
                deployFlag="true"
        else
                deployFlag="false"
        fi
}
#判断单行字符串是否等于指定字符串


#循环判断文件中所有服务名称是否包含在列表中，有一个不包含则退出循环
getDeloyFlag(){
        for deployService  in $(cat $1)
        do
                echo $deployService     
                isContainsString $deployService $2
                if [ $deployFlag == "false" ];then
                        echo $deployFlag
                        break;
                fi
        done
}

#mysql数据库信息
mysql_host="127.0.0.1"
mysql_port="3306"
mysql_user="root"
mysql_password=""
mysql_dbname=""
#jenkins 账户信息
jenkins_username=""
jenkins_passwd=""
#build number
currentNumber=`cat buildNumber.txt`

#根据service名字获取jenkins上对应的构建job
function getServiceBuildUrl(){
        select_sql="select job_url  from insaic.service_list where service_name='$1';"
        #mysql -uroot -pPass@word01 -N  -e "${sql}" > serviceCount.txt
        mysql -h${mysql_host} -P${mysql_port}  -u${mysql_user}  -p${mysql_password}  -N  -e "${select_sql}" > serviceJenkinsBuildUrl.txt
        echo `cat serviceJenkinsBuildUrl.txt`
}
#根据service名字获取数据库中是否有对应数据
function getServiceCountFromDb(){
        select_sql="select count(*)  from insaic.service_list where service_name='$1';"
        #mysql -uroot -pPass@word01 -N  -e "${sql}" > serviceCount.txt
        mysql -h${mysql_host} -P${mysql_port}  -u${mysql_user}  -p${mysql_password}  -N  -e "${select_sql}" > serviceCount.txt
        echo `cat serviceCount.txt`
}
#触发jenkins构建
function triggerJenkinsBuild(){
        curl -X POST '$1/buildWithParameters?delay=0sec'  --user $jenkins_username:$jenkins_passwd
}

#获取job构建状态，true/false eg: http://jenkins.yk.com:8080/job/common-code-service/lastBuild/api/json
function getBuildStatus(){
        echo `curl -u $jenkins_username:$jenkins_passwd  $1/lastBuild/api/json | jq  .building `
}
#获取job构建结果，SUCCESS
function getBuildResult(){
        echo `curl -u $jenkins_username:$jenkins_passwd  $1/lastBuild/api/json | jq '.result' |sed 's/\"//g'`
}
#获取之前已部署的应用
function getResult(){
        select_sql="select service_name  from insaic.result where deploy_flag=0;"
        mysql -h${mysql_host} -P${mysql_port}  -u${mysql_user}  -p${mysql_password}  -N  -e "${insert_sql}" > alreadyDeployedServices.txt
        echo `cat alreadyDeployedServices.txt`

}
#插入数据
function insertResult(){
        insert_sql="INSERT INTO result(service_name,insert_time,deploy_flag) VALUES('$1','$2',0)"
        mysql -h${mysql_host} -P${mysql_port}  -u${mysql_user}  -p${mysql_password}  -N  -e "${insert_sql}" > serviceCount.txt

}
#更新数据,全部部署完成，添加结束标识方便后续部署
function updateResultFlag(){
        update_sql="UPDATE result SET deploy_flag = '1' WHERE deploy_flag = '0' "
        mysql -h${mysql_host} -P${mysql_port}  -u${mysql_user}  -p${mysql_password}  -N  -e "${update_sql}" > serviceCount.txt

}


#判断是否执行成功
functionResult=""
function isExecSuccessful(){
        if [ $? = 0 ];then
                echo "0"
        fi
}




#serviceJenkinsBuildUrl=`getServiceBuildUrl common-code-service `
#echo -e $serviceJenkinsBuildUrl
#serviceCount=`getServiceCountFromDb bigdata-provider`
#echo -e $serviceCount

deploy_id=`date +%Y%m%d%H%M`
#循环时间
sleep_time=10
isBuilding=true
buildResult=""
for deployService  in $(cat $1)
do
                serviceCount=`getServiceCountFromDb $deployService`
                if [[ $serviceCount == "1" ]]; then
                        deployFlag="true"
                else
                        deployFlag="false"
                        break;
                fi
done

echo "是否满足部署条件：$deployFlag"
if [ $deployFlag == "true" ];then
        echo "------------------开始执行部署-----------------"
        #从上次执行失败的job开始部署===================
        
        
        for deployService  in $(cat $1)
        do
                serviceJenkinsBuildUrl=`getServiceBuildUrl $deployService`
                echo "------------------部署jenkins job为：$deployService($serviceJenkinsBuildUrl)-----------------"
                echo "开始部署" 
                # eg：serviceJenkinsBuildUrl ：http://jenkins.yk.com:8080/job/common-code-service/
                triggerJenkinsBuild $serviceJenkinsBuildUrl
                #执行完毕部署后，每隔10秒循环获取构建是否完成
                while [[ isBuilding ]]; do
                       isBuilding= `getBuildStatus $serviceJenkinsBuildUrl`
                       if ( "false" = "$isBuilding" );then
                                break
                       fi
                done
                #构建完成标识为false时，判断构建结果是否成功，如果成功则插入数据到mysql中，如果失败结束任务
                currentJobBuildResult=`getBuildResult  $serviceJenkinsBuildUrl`


                if [[ "SUCCESS" == "$currentJobBuildResult" ]]; then
                        echo "-------------------$deployService部署成功！-------------------"

                        #插入记录到result表中

                        #记录build的docker tag号生成报告，方便后续生产环境部署

                else
                        echo "-------------------$deployService部署失败，请解决报错后继续执行！-------------------"
                        break;
                fi
                
        done

        #检查
        echo "-------------------所有服务部署成功！-------------------"
        #当前部署完成后flag全部置为1
        updateResultFlag
else
        echo "-------------------部署任务中存在数据库中未维护的服务，请检查后重新部署！-------------------"
fi
