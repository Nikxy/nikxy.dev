---
title: Simple serverless auth service on AWS
date: 2023-09-28
draft: false

description: Documentation of a simple JWT auth service i have developed on AWS
showAuthor: true
categories: ["AWS"]
tags: ["REST API", "Lambda", "Cloud Formation", "AWS SAM", "Localstack"]
---

{{< alert >}}
This is a POC and shouldn't be used in production as it is **NOT** protected against attacks.
{{< /alert >}}

![Service Diagram](diagram.png)

## Summary

I'm planning on uploading demo projects and i needed an auth service.  
Instead of creating a seperate auth logic in each project i decided to create a simple serverless JWT auth service to use in all projects.  
I have deployed it on AWS cloud with lambda and dynamodb using a self hosted Gogs and Jenkins CI/CD.

For running the integration tests i run the lambda and api gateway locally with AWS SAM.  
Jenkins is running in a docker container and there is a caviat with that aproach which i will explain later.  
`NOTE:` AWS SAM is using docker to run lambda locally in containers.

### Features

-   Each project has its own "domain" with its JWT secret and users.
-   The JWT secrets can be easily rotated using AWS Secrets Manager built-in features with a simple lambda function.

### In plan features

-   Use public-private secret keys instead of a simple JWT secret string.
-   Comply with OAuth2 specifications.
-   Create an option for other services to check if user session is still valid.

## API Flow

### Login

1. Client sends http post to the auth service with json body, example:

```
{
    "domain":"demo",
    "username":"demo",
    "password":"password"
}
```

2. Lambda extracts JWT secrets from secrets manager and if specified domain exists continues, otherwise responds with invalid domain error.

3. Lambda checks if user exists in dynamodb and password is correct, otherwise responds with an invalid username or password error.

4. Lambda signs a JWT token using the domain secret and sends it to the client.

-   The JWT token contains the domain, username, session id and refresh token in the body.

### Authorization

1. Client sends a request to a service specifying the jwt token as bearer token in the Authorization header

2. Service gets its JWT secret from AWS Secrets Manager and checks if provided JWT token is valid.

3. `OPTIONAL` On critical operations the service can check in dynamodb if session is still valid.

### Token refreshing

## CI/CD

### Tools

-   [{{< icon "link" >}}**Gogs**](https://gogs.io/) - Self-hosted remote git repository, used to host the service's code.
-   [{{< icon "link" >}}**Jenkins**](https://www.jenkins.io/) - CI/CD pipeline tool, used to automate code testing and deployment.
-   [{{< icon "link" >}}**AWS Serverless Application Model (SAM)**](https://aws.amazon.com/serverless/sam/) - AWS open-source tool which is using Cloudformation under the hood to manage serverless applications, used to locally test and deploy the code to the cloud.
-   [{{< icon "link" >}}**Localstack**](https://localstack.cloud/) - A localy hosted AWS cloud emulation for testing.

### Flow

1. When code is pushed into the master branch, Gogs sends a webhook into Jenkins.
2. Jenkins pulls the latest changes and starts the pipeline.
3. Pipeline runs unit tests and integration tests using AWS SAM as a local deployment and Localstack as an emulation for the Secrets Manager and DynamoDB.
4. If the tests passed without failing the pipeline uses AWS SAM to deploy the Cloudformation template and the code.

### Jenkinsfile
I will show the important parts here, if you want to see the full Jenkins file:  
[{{< icon "link" >}}Get the full Jenkinsfile](Jenkinsfile)

For integration testing i use Localstack as an AWS emulation for the secrets manager and dynamodb.  
Before testing it should be running and populated with test data. I plan to implement localstack checks and population into the Jenkinsfile.

#### Dependencies
{{< scrollable-code >}}// Check if node_modules exists
TEST_NODE_MODULES_EXISTS = fileExists 'node_modules'
SRC_NODE_MODULES_EXISTS = fileExists 'src/node_modules'
// Check if AWS SAM exists
AWS_SAM_EXISTS = fileExists 'venv/bin/sam'
{{</ scrollable-code >}}
Here we check if the dependencies exist and write that to a variable to install if doesn't exists.

#### AWS settings
{{< scrollable-code >}}// AWS Settings
AWS_REGION = 'il-central-1'
AWS_STACK_NAME = 'auth-service'

// SAM uploads template and code to the specified S3 bucket
AWS_S3_BUCKET = 'my-cloudformation-bucket'
AWS_S3_PREFIX = 'auth-service'
{{</ scrollable-code >}}
AWS SAM is using CloudFormation under the hood, so we need to specify the stack name for the deployment and S3 bucket for template and code upload.

#### Integration Testing with AWS SAM
{{< scrollable-code >}}when {
    anyOf {
        changeset 'src/**';
        changeset 'tests/integration/**'
    }
}
{{</ scrollable-code >}}
This allows us to skip tests if code or tests haven't changed.

{{< scrollable-code >}}sh '''nohup venv/bin/sam local start-api \
--parameter-overrides ParameterKey=EnvironmentType,ParameterValue=test \
--warm-containers EAGER \
--container-host 172.17.0.1 --container-host-interface 0.0.0.0 \
--region ${AWS_REGION} -v /PATH_TO_WORKSPACE_ON_HOST \
> $WORKSPACE/sam.log 2>&1 &'''
{{</ scrollable-code >}}
We start sam in the background to continue with the pipeline.

Because Jenkins is running in a docker container we need to specify some arguments.  
Set the ip of the docker interface with --container-host and --container-host-interface to 0.0.0.0 to allow SAM to access the lambda container.

Also we need to setup the path to the source from the context of the docker host, for this i mounted a folder from the host to Jenkins workspaces folder and specified its path with the -v argument.

{{< scrollable-code >}}sh '''#!/bin/bash
    while [[ $(tail -n 1 sam.log) != *"CTRL+C"* ]]
        do echo "waiting for sam" && sleep 1
    done
'''
{{</ scrollable-code >}}
Waiting for AWS SAM to finish initializing.

{{< scrollable-code >}}def exitStatus =
    sh returnStatus: true, script: 'npm run test_ci:integration'
junit 'junit-integration.xml'
if (exitStatus != 0) {
    error 'Integration tests failed'
}
{{</ scrollable-code >}}
And running the tests.

### Cloudformation Template
{{< code-include template.yaml>}}