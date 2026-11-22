package com.bookstore.config;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.boot.ApplicationArguments;
import org.springframework.boot.ApplicationRunner;
import org.springframework.core.annotation.Order;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Component;

import java.util.List;
import java.util.Locale;

/**
 * Repairs legacy global unique indexes on shared book storage fields.
 *
 * The application shares the physical EPUB file between accounts, while each
 * account owns an independent Book row. Therefore neither book_path nor
 * file_hash can be globally unique, while file_hash remains unique within one
 * user account.
 */
@Component
@Order(10)
public class BookSchemaMigration implements ApplicationRunner {

    private static final Logger logger = LoggerFactory.getLogger(BookSchemaMigration.class);
    private static final String USER_FILE_HASH_INDEX = "uk_books_user_file_hash";

    private final JdbcTemplate jdbcTemplate;

    public BookSchemaMigration(JdbcTemplate jdbcTemplate) {
        this.jdbcTemplate = jdbcTemplate;
    }

    @Override
    public void run(ApplicationArguments args) {
        List<UniqueIndex> uniqueIndexes = jdbcTemplate.query(
            "SELECT INDEX_NAME, " +
                "GROUP_CONCAT(COLUMN_NAME ORDER BY SEQ_IN_INDEX SEPARATOR ',') AS INDEX_COLUMNS " +
                "FROM INFORMATION_SCHEMA.STATISTICS " +
                "WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'books' AND NON_UNIQUE = 0 " +
                "GROUP BY INDEX_NAME",
            (resultSet, rowNum) -> new UniqueIndex(
                resultSet.getString("INDEX_NAME"),
                resultSet.getString("INDEX_COLUMNS")
            )
        );

        boolean hasUserFileHashIndex = false;
        for (UniqueIndex index : uniqueIndexes) {
            String indexName = index.name;
            String columns = index.columns == null ? "" : index.columns.toLowerCase(Locale.ROOT);
            logger.info("Detected unique books index: {} ({})", indexName, columns);

            if ("user_id,file_hash".equals(columns) || "file_hash,user_id".equals(columns)) {
                hasUserFileHashIndex = true;
                continue;
            }

            if (("file_hash".equals(columns) || "book_path".equals(columns))
                    && isSafeIdentifier(indexName)) {
                jdbcTemplate.execute("ALTER TABLE books DROP INDEX `" + indexName + "`");
                logger.info("Dropped legacy global books.{} unique index: {}", columns, indexName);
            }
        }

        if (!hasUserFileHashIndex) {
            jdbcTemplate.execute(
                "ALTER TABLE books ADD UNIQUE INDEX " + USER_FILE_HASH_INDEX + " (user_id, file_hash)"
            );
            logger.info("Created per-user books file hash unique index: {}", USER_FILE_HASH_INDEX);
        }
    }

    private boolean isSafeIdentifier(String value) {
        return value != null && value.matches("[A-Za-z0-9_$]+") && !"PRIMARY".equalsIgnoreCase(value);
    }

    private static final class UniqueIndex {
        private final String name;
        private final String columns;

        private UniqueIndex(String name, String columns) {
            this.name = name;
            this.columns = columns;
        }
    }
}
