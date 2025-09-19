// ABOUTME: Tests for DataSource trait implementation
// Verifies that QDatabase correctly implements the DataSource trait

#[cfg(test)]
mod tests {
    use crate::data::database::QDatabase;
    use crate::data::datasource::DataSource;

    // This test verifies that QDatabase implements DataSource trait
    #[tokio::test]
    async fn test_qdatabase_implements_datasource() {
        // This test will only compile if QDatabase correctly implements DataSource
        fn assert_implements_datasource<T: DataSource>() {}
        assert_implements_datasource::<QDatabase>();
    }

    // Test that we can create a QDatabase and use it as a DataSource
    #[tokio::test]
    async fn test_qdatabase_as_datasource() {
        // Try to create a QDatabase (may fail if database doesn't exist)
        let result = QDatabase::new();

        if let Ok(mut db) = result {
            // Test that we can call DataSource trait methods
            // We need to explicitly use the trait methods via the trait
            let _changed = <QDatabase as DataSource>::has_changed(&mut db).await;
            let _conversation = <QDatabase as DataSource>::get_current_conversation(&db, None).await;

            // We're not checking results here as the database might not exist,
            // we're just verifying the trait methods can be called
        }
        // If database doesn't exist, that's OK for this test
    }

    // Test that we can box QDatabase as a DataSource
    #[tokio::test]
    async fn test_qdatabase_boxed_as_datasource() {
        let result = QDatabase::new();

        if let Ok(db) = result {
            // Box it as a DataSource trait object
            let mut datasource: Box<dyn DataSource> = Box::new(db);

            // Call trait methods through the trait object
            let _changed = datasource.has_changed().await;
            let _summaries = datasource.get_all_conversation_summaries().await;

            // Again, we're just verifying compilation and that methods can be called
        }
    }
}