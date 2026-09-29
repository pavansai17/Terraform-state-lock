# Terraform State Lock Mechanism

## Overview

In Terraform, if two developers create resources **at the same time** by running `terraform plan` and `terraform apply`, a **state lock** occurs to prevent any such disrupted scenarios. It ensures that only one operation can modify the state file at a time.

---

## The Problem

Imagine two developers working with the same `main.tf` for an EC2 instance:

| Developer 1 | Developer 2 |
|---|---|
| Runs `terraform plan` + `terraform apply` | Runs `terraform plan` + `terraform apply` at the same time |
| Config: `t2.micro`, 8GB, Ubuntu | Config: `t3.micro`, 12GB, Ubuntu |

Without state locking, both applies run concurrently against the **same state file**, causing **race conditions**, **state corruption**, or **overwritten infrastructure**.

---

## How State Lock Mechanism Works

1. If **Developer A** runs `terraform plan` and `terraform apply`, resource creation starts and the state file is generated.
2. This state file is stored as a **version** in an **S3 bucket**, and a **Lock ID** is generated in a **DynamoDB table** — this works as the backend.
3. If any other developer (**Developer B**) tries to create resources at the same time during the resource creation process, Developer B faces an error: **"state is in lock"** warning.

> Once the resource is created, the **Lock ID is released** automatically.

**Backend components:**
- **S3 bucket** → stores the state file (with versioning enabled: `version1.tfstate`, `version2.tfstate`, ...)
- **DynamoDB table** → stores the Lock ID (e.g., `1234`, `4567`) for locking

---

## Implementation of State Lock Mechanism

### Prerequisites
- AWS Account
- Terraform installed
- AWS CLI configured

### Step 1: Create an S3 Bucket and Enable Versioning

```bash
aws s3api create-bucket   --bucket state-lock-m14-218014314814-ap-south-1-an   --region ap-south-1   --create-bucket-configuration LocationConstraint=ap-south-1

aws s3api put-bucket-versioning   --bucket state-lock-m14-218014314814-ap-south-1-an   --versioning-configuration Status=Enabled
```

### Step 2: Create a DynamoDB Table

Create a DynamoDB table with the **partition key name as `LockID`**:

```bash
aws dynamodb create-table   --table-name state-lock-db   --attribute-definitions AttributeName=LockID,AttributeType=S   --key-schema AttributeName=LockID,KeyType=HASH   --provisioned-throughput ReadCapacityUnits=5,WriteCapacityUnits=5
```

### Step 3: Create `backend.tf`

```hcl
terraform {
  backend "s3" {
    bucket         = "state-lock-m14-218014314814-ap-south-1-an"
    key            = "state-file/terraform.tfstate"
    region         = "ap-south-1"
    encrypt        = true
    dynamodb_table = "state-lock-db"
  }
}
```

### Step 4: Initialize Terraform

Run this after creating `provider.tf` and `backend.tf`:

```bash
terraform init
```

### Step 5: Create `main.tf` and Launch an EC2 Instance

```hcl
resource "aws_instance" "ins-01" {
  ami           = var.ami
  instance_type = var.instance_type
  key_name      = aws_key_pair.deployer.key_name # attaching a key pair to the instance

  tags = {
    Name = "instance-01" # instance name
  }
}
```

### Step 6: Test the Lock — Open Two Terminals

In **both terminals**, run the same commands:

```bash
terraform plan
terraform apply
```

One terminal acquires the state lock and proceeds.
The other terminal waits and then fails with:

```
Error: Error acquiring the state lock
Lock Info:
  ID:        1234
  Operation: OperationTypeApply
  ...
```

### Step 7: Verify in AWS

- In **S3** → the state file (`terraform.tfstate`) is stored as a **version**
- In **DynamoDB** → the **LockID** is generated in the table while the operation runs, and released once the resource is created

---

## Architecture Flow

```
main.tf ──► terraform plan/apply ──► state file ──► S3 bucket (versioned)
                                          │
                                    Lock ID ───────► DynamoDB table (LockID)
                                          │
                                    EC2 created in AWS
```

---

## File Structure

```
project/
├── provider.tf      # AWS provider configuration
├── backend.tf       # S3 + DynamoDB backend (locking)
├── main.tf          # EC2 instance resource
├── variable.tf      # Input variables (ami, instance_type)
└── output.tf        # Outputs (instance_id, public IP, etc.)
```

---

## Cleanup

```bash
terraform destroy
```

> Optionally delete the S3 bucket and DynamoDB table after testing to avoid charges.

---

## Summary

| Concept | Purpose |
|---|---|
| **State Lock** | Prevents concurrent modifications to the same state file |
| **S3 Backend** | Remote, versioned storage of `terraform.tfstate` |
| **DynamoDB Lock Table** | Stores Lock ID to enforce exclusive access |
| **`encrypt = true`** | Secures the state file at rest in S3 |

> State locking happens automatically with the S3 backend + DynamoDB table — no extra flags needed!
