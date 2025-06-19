provider "aws" {
  region = var.aws_region
}

resource "aws_instance" "example1" {
    ami = var.ami_value
    instance_type = var.instance_type_value
    vpc_security_group_ids = [aws_security_group.mysg.id]
    iam_instance_profile   = aws_iam_instance_profile.s3_creator_uploader_profile.name 
    user_data = base64encode(templatefile("./script.sh", {
    repo_url     = var.repo_url_value
    java_version = var.java_version_value
    repo_dir_name= var.repo_dir_name
    stop_after_minutes = var.stop_after_minutes
    s3_bucket_name = var.s3_bucket_name
  }))

  tags = {
    Name = "MyInstance"
  }

  depends_on = [
    aws_s3_bucket.example
  ]
}



resource "aws_security_group" "mysg" {
  name = "webig"

  ingress {
    description = "HTTP from vpc"
    from_port = 80
    to_port = 80
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "ssh"
    from_port = 22
    to_port = 22
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  tags = {
    Name = "Web.sg"
  }

  
}

resource "aws_s3_bucket" "example" {
  bucket = var.s3_bucket_name 

  tags = {
    Name        = "My bucket"
    Environment = "Dev"
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "example" {
  bucket = aws_s3_bucket.example.id

  rule {
    id     = "delete_app_logs_after_7_days"
    status = "Enabled"

    filter {
      prefix = "app/logs/"
    }

    expiration {
      days = 7
    }
  }
}


resource "aws_iam_role" "s3_creator_uploader_role" {
  name = "s3_creator_uploader_access_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Sid    = ""
        Principal = {
          Service = "ec2.amazonaws.com" 
        }
      },
    ]
  })

  tags = {
    Name = "S3CreatorUploaderRole"
  }
}

resource "aws_iam_policy" "s3_creator_uploader_policy" {
  name        = "s3_creator_uploader_policy"
  description = "Provides permissions to create S3 buckets and upload objects, explicitly denying read/download"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = [
          "s3:CreateBucket", 
          "s3:PutObject",    
          "s3:PutObjectAcl", 
        ]
        Resource = "*" 
      },
      {
        Effect   = "Deny"     
        Action   = [
          "s3:Get*",  
          "s3:List*", 
        ]
        Resource = "*" 
      },
    ]
  })
}

# Attach S3 Creator/Uploader Policy to the Role
resource "aws_iam_role_policy_attachment" "s3_creator_uploader_attachment" {
  role       = aws_iam_role.s3_creator_uploader_role.name
  policy_arn = aws_iam_policy.s3_creator_uploader_policy.arn
}

# --- IAM Instance Profile for S3 Creator/Uploader Role ---
# An instance profile is required to attach an IAM role to an EC2 instance.
resource "aws_iam_instance_profile" "s3_creator_uploader_profile" {
  name_prefix = "s3-creator-uploader-profile"
  role = aws_iam_role.s3_creator_uploader_role.name # Reference the role created above

  tags = {
    Name = "S3CreatorUploaderInstanceProfile"
  }
}
