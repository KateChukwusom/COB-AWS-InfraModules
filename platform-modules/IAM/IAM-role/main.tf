/*The essence of locals is to enforce COB's naming convention
The convention is baked in by the interpolation of team name and environment 
*/

# locals {
#   role_name = "${}"
# }


resource "aws_iam_role" "COB_iam_module_name" {
  name = "iam_role"
  assume_role_policy = data.aws_iam_policy_document.COB_iam_trust_policy.json

  tags = {
    tag-key = "tag-value"
  }
}

data "aws_iam_policy_document" "COB_iam_trust_policy" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}