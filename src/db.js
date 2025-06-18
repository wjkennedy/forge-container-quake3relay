import { migrationRunner } from '@forge/sql';

export const CREATE_BOOKS_TABLE = `CREATE TABLE IF NOT EXISTS Books (
    id INT PRIMARY KEY AUTO_INCREMENT,
    title VARCHAR(200) NOT NULL,
    author VARCHAR(100) NOT NULL
)`;

export const createDBObjects = migrationRunner
    .enqueue('v001_create_books_table', CREATE_BOOKS_TABLE)

export const applyMigrations = async () => {
    const successfulMigrations = await createDBObjects.run();
    console.log('Migrations applied:', successfulMigrations);
    await migrationRunner
        .list()
        .then((migration) => migration.map((y) => console.log(`${y.name} migrated at ${y.migratedAt.toUTCString()}`)))
};

export const runMigration = async () => {
    try {
        await applyMigrations();
        return {
            body: JSON.stringify({ message: 'Migrations applied successfully' }),
            headers: {
                'Content-Type': ['application/json'],
            },
            statusCode: 200,
            statusText: 'OK'
        }
    } catch (error) {
        console.log('Error applying migration:', error);
    }
}