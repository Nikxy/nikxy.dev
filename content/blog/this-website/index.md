---
title: How I created this website and the thought I put into it
date: 2023-11-01
draft: false

description: Learn how I created my personal website using hugo and deployed it to AWS Amplify
showAuthor: true
categories: ["AWS", "Hugo"]
tags: ["Website", "Deployment", "Amplify"]
---

I have made websites in the past using different technologies ranging from writing static html to dynamic systems in PHP or using Wordpress, additionally I'm currently developing a webapp for my protfolio using React.

For my personal website and blog I wanted something simple to host, light on the browser and easy to add content to.
Wordpress requires a server to run and is a bit heavy from my experience, and writing clear HTML is a long process and hard to maintain.

I heard about hugo and how you can write your website in markdown and use git to manage your files.
So I decided to try it and after a couple days of tweaking to my liking, I got a working website with a build and deploy pipeline.

As hugo generates static content you can host it on any CDN. I decided to use AWS Amplify as it provides integration with Github, building and deployment.

You can check out the source of the website in the repository below:

{{< github repo="nikxy/nikxy.dev" >}}

## Deployment
I decided to put the website source in a git repository to be able to push and revert changes I make, I chose Github for this as it is the "industry standard" and can be easily integrated with Amplify and other services.

Amplify is connected to the Github repository and receives events from it. As soon as I push a change to the master branch Amplify will start its pipeline.

It will pull the source, build the static files using the specification file provided and deploy automatically.

### Build specifications
I imported the theme as a git submodule and had to call `git submodule update ...` to force it's download as it wasn't pulled otherwise.

Amplify has hugo installed but it's outdated for the theme so I had to download a newer version in the build.

I know it's a bit unoptimized as I'm not caching anything, I just haven't gotten my hands on optimizing it yet.
```yaml
version: 1
frontend:
  phases:
    build:
      commands:
        # Download the themes submodule
        - git submodule update --init --recursive --depth 1
        # Download and install newer version of hugo
        - wget https://github.com/gohugoio/hugo/releases/download/v0.119.0/hugo_extended_0.119.0_Linux-64bit.tar.gz
        - tar -xf hugo_extended_0.119.0_Linux-64bit.tar.gz hugo
        - mv hugo /usr/bin/hugo
        - rm -rf hugo_extended_0.119.0_Linux-64bit.tar.gz
        # Run the build
        - hugo
  artifacts:
    baseDirectory: public
    files:
      - '**/*'
  cache:
    paths: []
```

## Summary

I found hugo to be an easy system, easily customizable to your liking and very lightweight, you can get it up and running in a short timespan depending on how much you want to customize it.

I would easily recommend [Hugo](https://gohugo.io/) and the [Blowfish](https://blowfish.page/) theme it for static websites.

Amplify is a good service as well, it was easy to set-up with a few clicks in the AWS console. I still don't know all its features as I used only the frontend hosting but it provides backend as well.