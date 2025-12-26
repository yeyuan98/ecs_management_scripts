# ECS Management Scripts

## `postfix-email-forwarding-script.sh`

Chinese intro: 自动化配置邮件转发（阿里云测试可用），请按照阿里云DirectMail提示配置好后在ECS运行该脚本。

Is the complicated postfix setup for email forwarding from your host to a third-party mail forwarding service driving you crazy? Run this script - it is all automated.

Note that you need to finish setup with your forwarding service before proceeding. Such setup likely includes the following:

- Register your domain and hostname and add SPF, DKIM, DMARC and MX records
- Add your cloud public IP to whitelist
- Register your email address and setup SMTP passcode

This script is tested on Aliyun ECS with Aliyun DirectMail forwarding service (see below). Obviously, other Ubuntu servers should work out similarly.

- https://ecs.console.aliyun.com
- https://dm.console.aliyun.com

## License

This project is licensed with GPL v3.0.
