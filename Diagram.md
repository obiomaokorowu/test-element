+-----------+            +-------------+           +----------------+
| S3 Bucket |  ------->  | AWS Lambda  |  -------> | Processed Data |
| (Raw Data)|  Event     | (Merge CSV) |  Process  |    in S3       |
+-----------+            +-------------+           +----------------+
|
v
+-----------------+
| Visualization   |
| AWS QuickSight  |
+-----------------+