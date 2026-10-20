// 첫 기동 때 mongosh 로 실행된다. `db` 는 MONGO_INITDB_DATABASE 로 지정한 DB.
db.createCollection('users', {
  validator: {
    $jsonSchema: {
      bsonType: 'object',
      required: ['email', 'name', 'createdAt'],
      properties: {
        email:     { bsonType: 'string', pattern: '^.+@.+$' },
        name:      { bsonType: 'string', maxLength: 100 },
        createdAt: { bsonType: 'date' },
      },
    },
  },
});
db.users.createIndex({ email: 1 }, { unique: true });

db.createCollection('orders', {
  validator: {
    $jsonSchema: {
      bsonType: 'object',
      required: ['userId', 'amount', 'status', 'createdAt'],
      properties: {
        userId:    { bsonType: 'objectId' },
        amount:    { bsonType: ['int', 'long', 'double', 'decimal'], minimum: 0 },
        status:    { enum: ['PENDING', 'PAID', 'CANCELLED'] },
        createdAt: { bsonType: 'date' },
      },
    },
  },
});
db.orders.createIndex({ userId: 1, createdAt: -1 });

// 시드 데이터
const now = new Date();
const { insertedIds } = db.users.insertMany([
  { email: 'alice@example.com', name: 'Alice', createdAt: now },
  { email: 'bob@example.com',   name: 'Bob',   createdAt: now },
]);
db.orders.insertOne({ userId: insertedIds[0], amount: 15000, status: 'PAID', createdAt: now });
