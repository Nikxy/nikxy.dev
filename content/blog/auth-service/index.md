---
title: Simple serverless auth service on AWS
date: 2023-10-02
draft: false

description: Documentation of a simple JWT auth service I have developed on AWS
showAuthor: true
categories: ["AWS"]
tags: ["REST API", "Lambda", "Cloud Formation", "AWS SAM", "Localstack"]
---
<style>
    .highlight > pre, figure {
        margin:0 !important;
    }
    p {
        margin-bottom: .25rem !important;
    }
</style>
I'm currently learning for the [{{< icon "link" >}}AWS Certified Developer - Associate](https://aws.amazon.com/certification/certified-developer-associate/) and for getting practical knowledge I'm developing a few demo projects and I need authentication in some of them.  
Instead of creating a seperate auth logic in each project I decided to create a simple serverless JWT auth service to use in all projects.

I have deployed it on AWS cloud using lambda, dynamodb and secrets manager. For CI/CD I used self-hosted Gogs and Jenkins.

## Diagram

![Service Diagram](diagram.webp)

## Features

-   Each project has its own `domain` with its JWT secret and users.
-   The JWT secrets can be easily rotated using AWS Secrets Manager built-in features.

## In plan features

-   Use public-private secret keys instead of a simple JWT secret string.
-   Comply with OAuth2 specifications.

## GitHub Repository

{{< github repo="nikxy/lambda-auth" >}}
{{< spacing 1rem >}}
{{< alert >}}
This is a POC and shouldn't be used in production as it is **NOT** protected against attacks.
{{< /alert >}}

## API Flow

The api follows the REST api principle.

### Authentication

1. Client sends a POST to `/login` with json body, example:
    ```json
    {
        "domain":"demo",
        "username":"demo",
        "password":"password"
    }
    ```

2. Lambda extracts JWT secrets from secrets manager and if specified domains secret exists continues, otherwise responds with invalid domain error.
3. Lambda checks if user exists in dynamodb and password is correct, otherwise responds with an invalid username or password error.
4. Lambda signs a JWT token using the domain secret and sends it to the client.
-   The JWT token contains the domain, username, session token and refresh token in the body.

### Token refreshing

1. Client sends a GET to `/refresh` specifying the token in the Authorization header.
2. Lambda extracts the session & refresh tokens from JWT and checks if both are still valid.
3. Lambda creates and signs a new JWT token.

### Authorization
Authorization can be done in three ways:
* Use a lambda authorizer in the service api gateway.
* Use the jwt secret from the secrets manager and validate the token.
* Call the auth api on path `/auth` to check the validity of the token.

#### Lambda Authorizer
Setup an api gateway with an autorizer using the auth lambda.  
Example is provided with the api gateway `/auth` path in the cloudformation template.
1. Client sends a request with the jwt token in the header set by the cloudformation template to the api gateway.
2. Api gateway authorizers the request using the auth lambda
3. Api gateway continues to the integration

#### Validation with secret
1. Client sends a request to a service specifying the jwt token as bearer token in the authorization header set in cloudformation
2. Service gets its JWT secret from AWS Secrets Manager and checks if provided JWT token is valid.
3. `OPTIONAL` On critical operations the service can check in dynamodb if session is still valid.

    * This is not the best way as it isn't loosly coupled. API Check is planned for the future.

#### Use the auth API
1. Service send `GET` request to `/auth` path in the auth api with the user provided token
2. The auth api responds status code `200` if valid or `403` otherwise.


## CI/CD

Jenkins is running in a docker container and there is a caviat with that aproach which I will explain later.  
Secrets Manager and DynamoDB are emulated locally using Localstack.  
For running the integration tests I run the lambda and api gateway locally with AWS SAM.  
`NOTE:` AWS SAM is using docker to run lambda locally in containers.

### Tools

-   [{{< icon "link" >}}**Gogs**](https://gogs.io/) - Self-hosted remote git repository, used to host the service's code.
-   [{{< icon "link" >}}**Jenkins**](https://www.jenkins.io/) - CI/CD pipeline tool, used to automate code testing and deployment.
-   [{{< icon "link" >}}**AWS Serverless Application Model (SAM)**](https://aws.amazon.com/serverless/sam/) - AWS open-source tool which is using Cloudformation under the hood to manage serverless applications, used to locally test and deploy the code to the cloud.
-   [{{< icon "link" >}}**Localstack**](https://localstack.cloud/) - A localy hosted AWS cloud emulation for testing.

### Flow

1. When code is pushed into the master branch, Gogs sends a webhook into Jenkins.
2. Jenkins pulls the latest changes and starts the pipeline.
3. Pipeline runs unit tests and integration tests using AWS SAM as a local deployment and Localstack as an emulation for the Secrets Manager and DynamoDB.
4. If the tests passed the pipeline uses AWS SAM to deploy the Cloudformation template and the code.

### Jenkinsfile
I will show the important parts here, if you want to see the full Jenkins file:  
[{{< icon "link" >}}Complete Jenkinsfile on GitHub](https://github.com/Nikxy/lambda-auth/blob/master/Jenkinsfile)

For integration testing I use Localstack as an AWS emulation for the secrets manager and dynamodb and AWS SAM for running lambdas and api gateway locally.  
Before testing it should be running and populated with test data. Later I plan to implement localstack checks and population into the Jenkinsfile.

#### Config

Load config using Jenkins configFileProvider:

```groovy
def CONFIG_FILE = configFile(fileId:'auth-service-config', variable:'config_json')
...
configFileProvider([CONFIG_FILE]) {
...
```

#### Dependencies
Check if the dependencies exist and write that to a variable to install in the pipeline.

```groovy
environment {
    // Check if node_modules has been installed in previous builds
    TEST_NODE_MODULES_EXISTS = fileExists 'node_modules'
    SRC_NODE_MODULES_EXISTS = fileExists 'src/node_modules'
    // Check if AWS SAM has been installed in previous builds
    AWS_SAM_EXISTS = fileExists 'venv/bin/sam'
}
```
I used python pip with venv to install **AWS SAM** only for the build environment

```groovy
sh(returnStdout:true, script: 'python3 -m venv venv && venv/bin/pip install aws-sam-cli')
```

If node modules exist from previous builds and no changes were made to the package files we can skip their installation, otherwise `npm ci` is called.

#### Integration Testing with AWS SAM

Starting AWS SAM is made with the folowing code:

```groovy
config = readJSON(file:config_json)

def sam_arguments = readFile "${WORKSPACE}/sam-api-arguments.sh"

sh "nohup venv/bin/sam $sam_arguments " +
    "--region $config.LOCALSTACK_TESTING_REGION "+
    "-v $config.DOCKER_HOST_WORKSPACE " +
    "--parameter-overrides EnvironmentType=test "+
    "LocalStack=$config.LOCALSTACK_URL " +
    "> $WORKSPACE/sam.log 2>&1 &"
```

First load the config from Jenkins using Config File Provider plugin.  
Example config:

```json
{
  "AWS_STACK_NAME":"auth-service",
  "AWS_DEPLOY_REGION":"eu-central-1",
  "LOCALSTACK_URL":"http://localstack/",
  "LOCALSTACK_TESTING_REGION":"eu-central-1",
  "DOCKER_HOST_WORKSPACE":"/home/dev/jenkins_workspace/auth-service",
  "SAM_S3":"my-cloudformation"
}
```

Then load Sam arguments from the shell file and start sam in the background and log the output to sam.log

{{< badge >}}Caviat{{< /badge >}}
Because Jenkins is running in a docker container we need to specify some arguments.

* Install docker cli in Jenkins image and mount the docker socket for the Jenkins container
    ```yaml
    - /var/run/docker.sock:/var/run/docker.sock
    ```
* Test the connection by running docker ps from the jenkins container
* If you are getting `permission denied while trying to connect to the Docker daemon socket`, use the following command on the docker host:
    ```shell
    sudo setfacl --modify user:[user or ID]:rw /var/run/docker.sock
    ```

* Set the ip of the docker interface with --container-host and --container-host-interface to 0.0.0.0 to allow SAM to access the lambda container.

* The path to the workspace in the context of the docker host need to be specified.

Next wait for AWS SAM to finish initializing, with timeout in case SAM failed to start:

```bash
#!/bin/bash
time=0
while [[ $(tail -n 1 sam.log) != *"CTRL+C"* ]]
do 
    echo "waiting for sam"
    sleep 1
    if((time > 30)); then
        exit 1
    fi
    time=$((time+1))
done
```

And run the integration tests:

```groovy
def exitStatus =
    sh returnStatus: true, script: 'npm run test_ci:integration'
junit 'junit-integration.xml'
if (exitStatus != 0) {
    error 'Integration tests failed'
}
```

#### Deployment
After all tests were passed we deploy the code using the same AWS SAM:

```groovy
configFileProvider([CONFIG_FILE]) {
    withCredentials([usernamePassword(
            credentialsId: 'AWSJenkinsDeploy',
            usernameVariable: 'AWS_ACCESS_KEY_ID',
            passwordVariable: 'AWS_SECRET_ACCESS_KEY'
        )]) {
        script {
            config = readJSON(file:config_json)
            sh "venv/bin/sam deploy --no-progressbar "+
                "--stack-name $config.AWS_STACK_NAME "+
                "--region $config.AWS_DEPLOY_REGION "+
                "--s3-bucket $config.SAM_S3 --s3-prefix sam-$config.AWS_STACK_NAME " +
                "--on-failure ROLLBACK --capabilities CAPABILITY_NAMED_IAM"
        }
    }
}
```
* Use Jenkins credentials for AWS access key.
* Specify --no-progressbar for less output to the pipeline console.
* Specify --capabilities to enable creation of named IAM role specified in the CloudFormation template.

{{< alert >}}
AWS SAM uses CloudFormation under the hood, so we need to specify s3 bucket where to upload the template and code. I also specified a prefix to use one bucket for all projects and differentiate objects from other projects.
{{< /alert >}}

AWS SAM creates the following objects in the s3 bucket:

```shell
S3://bucket-name
└── prefix
    ├── ****.template # CloudFormation template file
    └── ************* # Zip archive of the code
```

`NOTE` Each deployment a new object is created for the modified template or code.

## Summary

This is my first project on AWS, I used it as a learning ground for my AWS Certifications and Jenkins. I learned a lot while creating it and I'm excited to use the AWS cloud and Jenkins.  
For future projects I plan to use also AWS's CI/CD with CodePipeline.