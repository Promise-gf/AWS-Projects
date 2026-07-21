# GROUP 9 – AWS Beginner Cloud Lab

A step-by-step practical guide for beginners to build a small, working cloud environment on AWS.

## Objective

This lab walks a complete beginner through building a small, working cloud environment on AWS. By the end, the learner will have:

- A Linux server running on EC2
- A Dockerized application deployed to it
- Source code pulled directly from GitHub
- A connected S3 bucket used for storage

The goal is to understand how compute (EC2), containers (Docker), version control (GitHub), and storage (S3) fit together in a real deployment — not just to click through the AWS console.

## What You Will Build

A simple architecture:

```
local machine → push code to GitHub → EC2 instance pulls code
→ Docker builds and runs the app in a container on the instance
→ app/script reads & writes files to an S3 bucket for storage
```

## Prerequisites

- A free AWS account (Free Tier eligible) with billing alerts turned on
- A GitHub account
- A terminal on your laptop (Terminal on Mac/Linux, PowerShell or WSL on Windows) — or VS Code's integrated terminal
- Basic comfort typing commands — no prior AWS experience required

---

## Part 1 — Linux Basics You Need First

EC2 instances in this lab run Amazon Linux, so a handful of Linux commands are needed throughout. Practice these before continuing:

```bash
pwd                 # show current directory
ls -la              # list files, including hidden ones
cd my-folder        # change directory
sudo <command>      # run a command as administrator
mkdir project       # create a folder
cat file.txt        # print a file's contents
df -h               # check disk space
```

Keep this list nearby — every step below is built from these commands plus a few new ones (`git`, `docker`, `aws`).

---

## Part 2 — Launch an EC2 Instance

1. Sign in to the AWS Console and search for "EC2".
2. Click **Launch Instance**.
3. Name it: `group9-lab-server`.
4. Choose an Amazon Machine Image (AMI): **Amazon Linux 2023** (Free Tier eligible).
5. Choose instance type: **t2.micro** or **t3.micro** (Free Tier eligible).
6. Create a new key pair (e.g. `group9-key`), download the `.pem` file, and store it safely — it cannot be downloaded again.
7. Under Network Settings, allow **SSH (port 22)** from "My IP", and allow **HTTP (port 80)** from Anywhere so you can view the app later.
8. Leave storage at the default 8 GB gp3 volume.
9. Click **Launch Instance** and wait until the instance state shows "Running".

> **Note:** Write down the instance's Public IPv4 address — you'll need it to connect.

---

## Part 3 — Connect to the Instance via SSH

From your local terminal, move into the folder holding your key file and lock down its permissions (Mac/Linux):

```bash
chmod 400 group9-key.pem
ssh -i group9-key.pem ec2-user@<YOUR_EC2_PUBLIC_IP>
```

On Windows, use the same command inside WSL or Git Bash, or use PuTTY with a converted `.ppk` key.

Once connected, you're inside the Linux server — run the Part 1 commands to confirm you're really there (`pwd`, `ls`, `df -h`).

---

## Part 4 — Install Docker on the EC2 Instance

Update packages and install Docker:

```bash
sudo yum update -y
sudo yum install docker -y
sudo service docker start
sudo usermod -aG docker ec2-user
```

Log out and reconnect (`exit`, then `ssh` in again) so the group permission takes effect. Confirm Docker is working:

```bash
docker --version
docker run hello-world
```

---

## Part 5 — Push Your Project to GitHub, Then Pull It Onto EC2

### 5.1 Build the project locally in VS Code

Before EC2 can pull anything, your app's code needs to exist in a GitHub repository. Create a project folder locally (e.g. in VS Code) containing these files:

**`server.js`**

```javascript
const http = require("http");

const server = http.createServer((req, res) => {
  res.writeHead(200, { "Content-Type": "text/plain" });
  res.end("Hello from Group 9 Cloud Lab!\n");
});

server.listen(80, () => {
  console.log("Server running on port 80");
});
```

**`package.json`**

```json
{
  "name": "group9-lab-app",
  "version": "1.0.0",
  "description": "Group 9 AWS Cloud Lab app",
  "main": "server.js",
  "scripts": {
    "start": "node server.js"
  }
}
```

**`.gitignore`**

```
node_modules
```

> **Note:** `Dockerfile` has no file extension — name it exactly "Dockerfile". VS Code and Windows sometimes silently append `.txt` or `.dockerfile` when saving; rename it in the Explorer panel if that happens, and confirm with `ls` that it shows as just "Dockerfile" before committing.

### 5.2 Push the project to GitHub

In the VS Code terminal, from inside the project folder:

```bash
git init
git add .
git commit -m "Initial commit: Group 9 lab app"
git branch -M main
git remote add origin https://github.com/Promise-gf/AWS-Projects.git
git push -u origin main
```

If the remote already exists, use `git remote set-url origin <url>` instead of `git remote add`. Create the empty repository on GitHub first (no README/license, to avoid push conflicts).

### 5.3 GitHub authentication from EC2

GitHub no longer accepts account passwords for git operations. When cloning from EC2, use a Personal Access Token (PAT) in place of the password:

1. GitHub → profile photo → **Settings** → **Developer settings** → **Personal access tokens** → **Tokens (classic)** → **Generate new token (classic)**
2. Check the "repo" scope, set an expiration, generate, and copy the token immediately (it's shown only once)
3. When prompted for a password during `git clone`, paste the token instead

### 5.4 Clone the repo onto EC2

```bash
sudo yum install git -y
git clone https://github.com/Promise-gf/AWS-Projects.git
cd AWS-Projects
```

`git clone` creates a folder matching the repo name (`AWS-Projects`) inside whatever directory you were in when you ran the command — typically `/home/ec2-user`. Confirm you're in the right place before continuing:

```bash
pwd
ls
```

`ls` should list `Dockerfile`, `server.js`, `package.json`, and `.gitignore`. This is the same repository your team pushes updates to from your own laptops — GitHub is what keeps the server and every teammate's copy of the code in sync.

---

## Part 6 — Build and Run the App in Docker

The cloned repo includes a Dockerfile using a multi-stage build — this keeps the final image smaller and avoids shipping build tools and dev dependencies, which also reduces the number of vulnerabilities a security scan will flag:

**`Dockerfile`**

```dockerfile
FROM node:22-alpine AS builder
WORKDIR /app
COPY package*.json ./
RUN npm install --omit=dev
COPY . .

FROM node:22-alpine
WORKDIR /app
COPY --from=builder /app .
EXPOSE 80
USER node
CMD ["node", "server.js"]
```

> **Note:** This uses `npm install` rather than `npm ci`, since `npm ci` requires a committed `package-lock.json`. If you'd rather use `npm ci` (more reproducible builds), run `npm install` locally once to generate `package-lock.json`, commit it, and switch the Dockerfile's `RUN` line back to `npm ci --omit=dev`.

Build and run the container on the EC2 instance:

```bash
docker build -t group9-app .
docker run -d -p 80:80 --name group9-container group9-app
docker ps
```

Open a browser and visit `http://<YOUR_EC2_PUBLIC_IP>` to confirm the app is live — you should see "Hello from Group 9 Cloud Lab!"

### 6.1 Reading a vulnerability scan result

If your build environment reports something like "1 critical and 4 high vulnerabilities," that count alone isn't actionable — you need the actual CVE list to know what to fix. Get it with:

```bash
docker scout cves group9-app
```

(or the equivalent for whichever scanner is in use, e.g. `trivy image group9-app`). Depending on where the flagged issue lives:

- **npm package** → run `npm audit` and `npm audit fix`, or bump the package version in `package.json`
- **Alpine system library** (openssl, busybox, etc.) → try the latest Alpine point release tag, or switch base image (`node:22-slim` or a distroless Node image)
- **No patched version available yet** → sometimes acceptable to document and accept for a lab assignment

---

## Part 7 — Create and Connect an S3 Bucket

1. In the AWS Console, search for "S3" and click **Create bucket**.
2. Give it a globally unique name, e.g. `group9-cloudlab-storage-2026`.
3. Keep "Block all public access" turned **ON** (best practice for a beginner lab).
4. Click **Create bucket**.

Give the EC2 instance permission to talk to S3 by attaching an IAM Role (rather than hard-coding keys):

1. In the console, go to **IAM** → **Roles** → **Create role**.
2. Choose "AWS service" → "EC2".
3. Attach the policy `AmazonS3FullAccess` (fine for a lab; in production you'd scope this down).
4. Name the role `group9-ec2-s3-role` and create it.
5. Go to **EC2** → select your instance → **Actions** → **Security** → **Modify IAM role** → attach `group9-ec2-s3-role`.

Back on the EC2 terminal, install the AWS CLI (usually preinstalled on Amazon Linux) and test the connection:

```bash
aws s3 ls
echo "hello from group9 lab" > test.txt
aws s3 cp test.txt s3://group9-cloudlab-storage-2026/
aws s3 ls s3://group9-cloudlab-storage-2026/
```

> **Note:** If the `aws s3 ls` command works without any access keys configured, the IAM role is doing its job — this is the intended lesson: EC2 talks to S3 through a role, not stored credentials.

---

## Part 8 — Verify the Full Loop

- **Linux** — you navigated and managed files on the instance directly
- **EC2** — the instance is running and reachable at its public IP
- **GitHub** — the app's code came from a repo clone, not manual upload
- **Docker** — the app runs inside a container, built from a Dockerfile
- **S3** — a file was written from the EC2 instance into a bucket, using an IAM role

---

## Part 9 — Cleanup (Important)

AWS Free Tier has limits — always tear down lab resources when finished to avoid charges:

- Stop the running container: `docker stop group9-container`
- In the EC2 console: select the instance → Instance State → **Terminate**
- In the S3 console: empty the bucket, then delete it
- In IAM: delete the `group9-ec2-s3-role` if it's no longer needed

---

## Troubleshooting Quick Reference

| Issue                                                                                           | Fix                                                                                                   |
| ----------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------- |
| `Permission denied (publickey)` on SSH                                                          | Check `chmod 400` was run and you're using the right `.pem` file and username (`ec2-user`)            |
| `Connection timed out` on SSH                                                                   | Check the Security Group allows port 22 from your current IP                                          |
| `remote: Invalid username or token. Password authentication is not supported` on git clone/push | Use a Personal Access Token instead of your GitHub password                                           |
| `failed to read dockerfile: open Dockerfile: no such file or directory`                         | You're not in the project folder; run `cd AWS-Projects` and confirm with `pwd`/`ls` before rebuilding |
| `npm ci` fails with "can only install with an existing package-lock.json"                       | Switch to `npm install` in the Dockerfile, or generate and commit `package-lock.json`                 |
| Site not loading in browser                                                                     | Check Security Group allows port 80, and the container is running (`docker ps`)                       |
| `Unable to locate credentials` on aws s3 commands                                               | The IAM role isn't attached to the instance yet, or needs a minute to propagate                       |

---

## Learning Outcomes

After completing this lab, a beginner should be able to explain, in their own words:

- The difference between compute and storage in the cloud
- Why containers make deployment repeatable
- Why source control matters when multiple people touch the same server
- Why IAM roles are safer than hard-coded credentials

(<../../IMAGES/Screenshot%20(405).png>)
(<../../IMAGES/Screenshot%20(406).png>)
(<../../IMAGES/Screenshot%20(407).png>)
(<../../IMAGES/Screenshot%20(408).png>)
(<../../IMAGES/Screenshot%20(409).png>)
(<../../IMAGES/Screenshot%20(410).png>)
(<../../IMAGES/Screenshot%20(411).png>)
